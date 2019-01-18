/* Tribal Wars 2 Farmbot v2019-01-18
This bot farms barbarian villages in Tribal Wars 2. It reads your battle reports and sends troops to your farms again.

## Features of This Bot

### Easy to Configure
+ Reads battle reports to identify your farm villages.
+ Uses the ‘Attack Again’ function in the battle report to attack each target village with your preferred composition of the army.
+ Uses the chrome web browser to support in-game configuration (e.g. reports filter).

### Efficient
+ Automatically activates correct villages to attack from the same villages again.
+ Improves efficiency of units distribution: Skips combination of attacking and defending village for which an attack has already been sent in the current cycle.
+ Applies heuristics to reduce the number of reports which need to be read to learn about all farming villages coordinates.

### Safe
+ Supports random breaks between farming cycles.
+ Stops the farming when the configured time limit is met to avoid perpetual activity on your account.

For details about how it works, see https://forum.botengine.org/t/farm-manager-tribal-wars-2-farmbot/1406

bot-catalog-tags:tribal-wars-2
*/

using System;
using System.Diagnostics;
using System.Linq;
using PuppeteerSharp;
using System.Collections.Generic;


//	Minimum timespan to break between farming cycles.
const int breakBetweenCycleDurationMinSeconds = 60 * 60;

//	Upper limit of a random additional time for breaking between farming cycles.
const int breakBetweenCycleDurationRandomAdditionMaxSeconds = 60 * 20;

const int numberOfFarmCyclesToRepeatMin = 1;

const int numberOfFarmCyclesToRepeatRandomAdditionMax = 0;

//	The bot ends a farming cycle when it has seen this many reports in a row with already covered coordinates of attacking and defending villages.
const int numberOfConsecutiveReportsWithAlreadyCoveredCoordinatesToEndCycle = 30;

const int waitForReportListButtonTimespanMaxSeconds = 120;
const int inGameDelaySeconds = 10;
const int cycleDurationMaxSeconds = 60 * 40;


/*
2018-08-10 Observed HTML:
<a href="#" class="icon-60x60-reports new-messages animation-jump" ng-click="open('report-list')" id="report-button" ng-class="{'new-messages animation-jump': gameDataModel.getNewReportCount() > 0}" tooltip="" tooltip-content="Berichte" internal-id="53">
*/
static string openReportListButtonXPath => "//a[@id='report-button']";

/*
2018-08-10 Observed HTML:
<a href="#" ng-class="{'btn-icon btn-orange': selectedTab != TAB_TYPES.Battle}">
*/
static string battleReportsButtonXPath => "//a[contains(@ng-class,'selectedTab != TAB_TYPES.Battle')]";

/*
2018-08-10 Observed HTML:
<li ng-repeat="report in reports" class="list-item row-even" ng-show="$index >= firstVisible &amp;&amp; $index <= lastVisible" ng-class="{'row-even': $index % 2 == 0, 'row-odd': $index % 2 == 1}">
*/
static string reportListItemXPath => "//li[@ng-repeat='report in reports']";

/*
2018-08-11 Observed HTML:
<a href="#" class="size-34x34 btn-orange btn-border btn-footer-small icon-34x34-attack" ng-click="attackAgain()" tooltip="" tooltip-content="Nochmal angreifen" internal-id="140"></a>
*/
static string inReportAttackAgainButtonXPath => "//a[@ng-click='attackAgain()']";

/*
2018-08-11 Observed HTML:
<a href="#" class="btn-orange btn-form btn-border no-padding" ng-class="{'btn-grey': armyEmpty || targetIsNoobProtected || officerOffersVisible}" ng-click="sendArmy('attack')" tooltip="" tooltip-content="Angreifen" internal-id="293">
*/
static string inSendArmyFormSendAttackButtonXPath => "//a[@ng-click=\"sendArmy('attack')\"]";

/*
2018-08-18 Observed HTML (as button was enabled):
<a href="#" ng-hide="noNavigation" class="size-34x34 btn-report-header icon-26x26-arrow-right btn-orange" ng-class="{true : 'btn-grey icon-inactive', false : 'btn-orange' }[(curReportIndex >= reportList.length - 1) &amp;&amp; lastPage]" ng-click="pageReport(1)"></a>
*/
static string inReportViewNavigateToNextReportButtonXPath => "//a[@ng-click='pageReport(1)']";

static string inBattleReportViewDetailsXPath => "//*[contains(@class, 'report-battle')]//table[@ng-show='showCasual']";

static string inBattleReportViewToggleDetailsButtonXPath => "//*[contains(@class, 'report-battle')]//*[@ng-click='toggleCasual()']";

static string inReportViewScrollWrapXPath => "//*[@ng-controller='ReportController']//*[contains(@class, 'scroll-wrap')]/parent::*";

static string openVillageInfoButtonXPath => "//*[@ng-click='openVillageInfo(character.getSelectedVillage().getId())']";

static string reportJumpToAttackerVillageXPath => "//*[starts-with(@ng-click, 'jumpToVillage(report[type].attVillage')]";

static string mapVillageContextMenuItemActivateXPath => "//*[contains(@class, 'context-menu-item') and contains(@class, 'activate')]";

static string customArmyWindowCloseButtonXPath => "//*[@ng-controller='ModalCustomArmyController']//*[@ng-click='closeWindow()']";

static string browserPageVisibilityGuide => "If you see this happen all the time, make sure that the game is visible in the web browser.";

static string switchVillageChatWindowGuide => "If you see this happen frequently, make sure that no chat window is open in the game. (https://forum.botengine.org/t/farm-manager-tribal-wars-2-farmbot/1406/108?u=viir)";

Host.Log("Welcome! - ¡Bienvenido! - Bienvenue! ---- This is the Tribal Wars 2 Farmbot. I read your battle reports and send troops to your farms again. To learn more about how I work, see https://forum.botengine.org/t/farm-manager-tribal-wars-2-farmbot/1406. In case you have any questions, feel free to ask at https://forum.botengine.org");

var cycleCount = RandomIntFromMinimumAndRandomAddition(numberOfFarmCyclesToRepeatMin, numberOfFarmCyclesToRepeatRandomAdditionMax);

Host.Log($"According to the configuration, I will repeat farming in { cycleCount } cycles. Between the farming cycles, I will take breaks with lengths between { breakBetweenCycleDurationMinSeconds / 60 } and { ((breakBetweenCycleDurationMinSeconds + breakBetweenCycleDurationRandomAdditionMaxSeconds) / 60) } minutes.");

var browserPage = WebBrowser.OpenNewBrowserPage();

browserPage.SetViewportAsync(new ViewPortOptions { Width = 1112, Height = 726, }).Wait();

browserPage.Browser.PagesAsync().Result.Except(new []{browserPage}).Select(page => { page.CloseAsync().Wait(); return 4;}).ToList();

Host.Log("Looks like opening the web browser was successful.");

Host.Delay(1);

var sessionReport = new CycleReport{ BeginTime = Host.GetTimeContinuousMilli() / 1000 };

var logSessionStats = new Action(() =>
    {
        Host.Delay(1);
        Host.Log("In this session, " + sessionReport.StatisticsText);
        Host.Delay(1);
    });

var villageLocationsToNotAttack = new Dictionary<VillageLocation, BattleReportDetails>();

for(int cycleIndex = 0; ; ++cycleIndex)
{
	Host.Log("I am starting farming cycle " + cycleIndex + " of " + cycleCount + ".");

	if(0 < cycleIndex)
	{
		Host.Log("This is not the first farming cycle, I ask the browser to reload the page to get to a clean state.");
		browserPage.ReloadAsync(new NavigationOptions { Timeout = 15000, WaitUntil = new []{WaitUntilNavigation.DOMContentLoaded} }).Wait();
		Host.Delay(1111);
	}

	Host.Delay(1111);

	var waitForReportListButtonStopwatch = Stopwatch.StartNew();

	while(true)
	{
		Host.Log("I did not find the button to open the report list. Maybe the game is still loading. (The location of the current page is '" + browserPage.Url + "'). If you have not done this yet, please log in and enter the game in the web browser I opened when the script started. For now, I keep looking for that button to appear....");
	
		if(WaitForOpenReportListButton(15000) != null)
			break;

		if(waitForReportListButtonTimespanMaxSeconds < waitForReportListButtonStopwatch.Elapsed.TotalSeconds)
		{
			var	message = "Did not find the button to open the report list while waiting for " + ((int)waitForReportListButtonStopwatch.Elapsed.TotalSeconds) + "seconds. Therefore I stop the bot."; 
			Host.Log(message);
			throw new ApplicationException(message);
		}
	}

	Host.Log("Found the button to open the report list.");
	Host.Log("Please configure filtering in the reports list now. I will wait for " + inGameDelaySeconds + " seconds before continuing. In case you need more time to configure the game, you can pause the bot.");

	Host.Delay(1000 * inGameDelaySeconds);

	var urlWithoutCharIdMatch = System.Text.RegularExpressions.Regex.Match(browserPage.Url ?? "", ".*(?<!&character_id=.*)");

	Host.Log("Url without character id: " + (urlWithoutCharIdMatch.Success ? ("'" + urlWithoutCharIdMatch.Value + "'") : "no match"));

	var openReportListButton = WaitForOpenReportListButton(1000);

	if (openReportListButton == null)
	    throw new NotImplementedException("Did not find openReportListButton.");

	Host.Log("Found the button to open the report list. I click on this button....");

	Host.Delay(333);

	if(!AttemptClickAndLogError(() => WaitForOpenReportListButton(1000)))
		throw new NotImplementedException("Did not find openReportListButton.");

	var battleReportsButton = WaitForReference(() =>
	    browserPage.XPathAsync(battleReportsButtonXPath).Result.FirstOrDefault(), 10000);

	if(battleReportsButton == null)
	{
		Host.Log("It looks like opening the report list was not successful. Please make sure the zoom level in the browser window is set to 100%.");
		throw new NotImplementedException("Did not find button to switch to battle reports.");
	}

	var firstReportItem = WaitForReference(() =>
	    browserPage.XPathAsync(reportListItemXPath).Result.FirstOrDefault(), 3000);

	if (firstReportItem == null)
	    throw new NotImplementedException("Did not find any report in the report list.");

	Host.Log("Found at least one report item in the reports list.");

	//	AttemptClickAndLogError(() => openReportListButton);

	Host.Delay(444);

	var reports = WaitForReference(() => browserPage.XPathAsync(reportListItemXPath).Result, 1000);

	if(reports == null)
	    throw new NotImplementedException("Did not find the reports.");

	var parsedReportItems = reports.Select(ParseReportListItem).ToList();

	//	Host.Log("parsedReportItems:\n" + Newtonsoft.Json.JsonConvert.SerializeObject(parsedReportItems));
	Host.Log("Number of parsed report items: " + parsedReportItems?.Count);

	Host.Log("Found a report in the report list. I click on it.");

	Host.Delay(333);

	AttemptClickAndLogError(() => parsedReportItems.FirstOrDefault().htmlElement);

	var cycleReport = new CycleReport{ BeginTime = Host.GetTimeContinuousMilli() / 1000 };

	var statisticsLogLastTime = 0;

	var logCycleStats = new Action(() =>
	    {
	        Host.Delay(1);
	        Host.Log("In the current cycle, " + cycleReport.StatisticsText);
	        Host.Delay(1);
	    });

	var numberOfConsecutiveReportsWithAlreadyCoveredCoordinatesInCycle = 0;
	var numberOfConsecutiveReportsWithSameCaption = 0;
	string lastReportCaption = null;

	while(true)
	{
		var cycleDuration = Host.GetTimeContinuousMilli() / 1000 - cycleReport.BeginTime;

		if(cycleDurationMaxSeconds < cycleDuration)
		{
			Host.Log("Stopping after " + cycleDuration + " seconds for safety.");
			break;
		}

		{
			var currentTime = (int)(Host.GetTimeContinuousMilli() / 1000);
			var statisticsLogLastTimeAge = currentTime - statisticsLogLastTime;
	
			if(60 * 5 < statisticsLogLastTimeAge)
			{
				logCycleStats();
				statisticsLogLastTime = currentTime;
				logSessionStats();
			}
		}

		Host.Delay(777);

		var customArmyWindowCloseButton =
			WaitForReference(() =>
				browserPage.XPathAsync(customArmyWindowCloseButtonXPath).Result?.FirstOrDefault(), 333);

		if(customArmyWindowCloseButton != null)
		{
			Host.Log("Looks like there is still an army window open. I click on the button to close it.");
	
			AttemptClickAndLogError(() => customArmyWindowCloseButton);
	
			Host.Delay(555);
	
			continue;
		}

		var currentReportHeader = WaitForReference(() =>
			browserPage.XPathAsync("//div[contains(@class,'report-header-wrapper')]").Result?.FirstOrDefault(), 333);

		var currentReportCaption =
			GetHtmlElementInnerText(currentReportHeader)?.Trim();

		Host.Log("Caption of the current open report: '" + ReportCaptionTextInSingleLine(currentReportCaption) + "'");

		if(lastReportCaption == currentReportCaption)
			++numberOfConsecutiveReportsWithSameCaption;
		else
			numberOfConsecutiveReportsWithSameCaption = 0;

		if(cycleReport.ReportsSeen.Any(report => report.Caption == currentReportCaption))
		{
			var	messageBase = "Hey, I have seen a report with the same caption before! ";

			if(2 < numberOfConsecutiveReportsWithSameCaption)
			{
				Host.Log(messageBase + "This has happened " + numberOfConsecutiveReportsWithSameCaption + " consecutive times. This could be caused by the the bug in the Tribal Wars 2 Web App which breaks reports display (https://forum.botengine.org/t/bug-in-tribal-wars-2-web-app-broken-report-display/1457). I start the process to recover from this bug.");

				var reportCaptionTimeMatch =
					System.Text.RegularExpressions.Regex.Match(lastReportCaption ?? "", @"\d{1,2}\:\d{2}\:\d{2}");

				var reportTimeToContinueAt =
					reportCaptionTimeMatch.Success ? reportCaptionTimeMatch.Value?.Trim() : null;

				if(!ReloadAndEnterReportAtTime(reportTimeToContinueAt))
				{
					Host.Log("Failed to reload the report list and continue. I end this cycle.");
					break;
				}
				numberOfConsecutiveReportsWithSameCaption = 0;
				numberOfConsecutiveReportsWithAlreadyCoveredCoordinatesInCycle = 0;
			}
			else
			{
				Host.Log(messageBase + "I skip this report and continue with the next one. " + browserPageVisibilityGuide);
			}

			goto navigateToNextReport;
		}

		var battleReportDetailsContainer =
			WaitForReference(() => browserPage.XPathAsync(inBattleReportViewDetailsXPath).Result.FirstOrDefault(), 333);

		if(battleReportDetailsContainer == null)
		{
			Host.Log("Did not find details container in battle report. Maybe this is a different kind of report, so I continue with the next report.");
			goto navigateToNextReport;
		}

		var battleReportDetailsContainerClass =
			battleReportDetailsContainer?.GetPropertyAsync("className").Result?.JsonValueAsync().Result?.ToString();
	
		if(battleReportDetailsContainerClass.Contains("ng-hide"))
		{
			Host.Log("Report details seem to be hidden, I try to open the report details.");
	
			if(!AttemptClickAndLogError(() => WaitForReference(() =>
				browserPage.XPathAsync(inBattleReportViewToggleDetailsButtonXPath).Result.FirstOrDefault(), 333)))
			{
				Host.Log("Did not find the button to toggle the report details. I end this cycle");
				break;
			}
	
			Host.Delay(555);
		}

		Host.Log("Parse the battle report details....");

		var parseBattleReportDetails = ParseBattleReportDetails(battleReportDetailsContainer);

		if(parseBattleReportDetails.IsFail)
		{
			Host.Log("Failed to parse the battle report details (" + parseBattleReportDetails.Error + "). I skip this report.");
			goto navigateToNextReport;
		}

		var	battleReportDetails = parseBattleReportDetails.Result;

		battleReportDetails.Caption = currentReportCaption;

		Host.Log("Battle report details:\n" + battleReportDetails);
		Host.Delay(1);

		cycleReport.ReportsSeen.Add(battleReportDetails);
		sessionReport.ReportsSeen.Add(battleReportDetails);

		if(!battleReportDetails.DefenderIsBarbarian)
		{
			villageLocationsToNotAttack[battleReportDetails.DefenderVillageLocation] = battleReportDetails;
			Host.Log("Looks like the defending village was not a barbarian village. I skip this report.");
			goto navigateToNextReport;
		}

		BattleReportDetails otherReportIndicatingToNotAttackHere;

		if(villageLocationsToNotAttack.TryGetValue(battleReportDetails.DefenderVillageLocation, out otherReportIndicatingToNotAttackHere))
		{
			var	sourceReportCaption = ReportCaptionTextInSingleLine(otherReportIndicatingToNotAttackHere.Caption);
			Host.Log("The details of report (‘" + sourceReportCaption + "’) indicated that I should not attack at " + battleReportDetails.DefenderVillageLocation + ". I skip this report.");
			goto navigateToNextReport;
		}

		if(cycleReport.ReportsForWhichAttackHasBeenSentAgain.Any(report =>
			report.AttackerVillageLocation.Equals(battleReportDetails.AttackerVillageLocation) &&
			report.DefenderVillageLocation.Equals(battleReportDetails.DefenderVillageLocation)))
		{
			Host.Log("An attack from " + battleReportDetails.AttackerVillageLocation + " to " + battleReportDetails.DefenderVillageLocation + " has already been sent in this cycle. I skip this report and continue with the next one.");
			Host.Delay(1);

			++numberOfConsecutiveReportsWithAlreadyCoveredCoordinatesInCycle;

			if(numberOfConsecutiveReportsWithAlreadyCoveredCoordinatesToEndCycle <
				numberOfConsecutiveReportsWithAlreadyCoveredCoordinatesInCycle)
			{
				Host.Log("The last " + numberOfConsecutiveReportsWithAlreadyCoveredCoordinatesInCycle + " reports I have seen contained combinations of attacking and defending village coordinates for which I have already sent attacks in this cycle. Because of this, I do not expect to find any more new farm coordinates in the next reports. I end this cycle.");
				break;
			}

			goto navigateToNextReport;
		}

		numberOfConsecutiveReportsWithAlreadyCoveredCoordinatesInCycle = 0;

		Host.Delay(1);
		Host.Log("This report looks like I should attack here.");
	
		var currentActiveVillageLocation = ReadCurrentActiveVillageLocation();
	
		if(!currentActiveVillageLocation.HasValue)
		{
			Host.Log("Failed to read the current active village location. I stop this cycle.");
			break;
		}
	
		Host.Log("Current active village location is " + currentActiveVillageLocation);
	
		Host.Delay(1);
	
		if(!currentActiveVillageLocation.Equals(battleReportDetails.AttackerVillageLocation))
		{
			Host.Log("Begin switching to village " + battleReportDetails.AttackerVillageLocation + ".");
	
			var scrollExpression =
				javascriptExpressionToGetFirstElementFromXPath("//*[@ng-controller='ReportController']//*[contains(@class, 'scroll-wrap')]/parent::*") +
				".scroll(0, 230)";
	
			var scrollResult = browserPage.EvaluateExpressionAsync(scrollExpression).Result;

			if(!AttemptClickAndLogError(() =>
				WaitForReference(() => browserPage.XPathAsync(reportJumpToAttackerVillageXPath).Result.FirstOrDefault(), 400)))
			{
				Host.Log("I did not find the button to jump to attackers village. I skip this report and continue with the next one.");
				goto navigateToNextReport;
			}

			Host.Delay(1777);

			if(!AttemptClickAndLogError(() => WaitForReference(() =>
				browserPage.XPathAsync(mapVillageContextMenuItemActivateXPath).Result.FirstOrDefault(), 3333)))
			{
				Host.Log("I did not find the context menu button to activate the village. I skip this report.");
				goto navigateToNextReport;
			}

			Host.Log("I clicked on the menu button to activate the village. Now I wait for the game to show " + battleReportDetails.AttackerVillageLocation + " as the active village.");

			Host.Delay(555);

			for(var i = 0; i < 7 && !currentActiveVillageLocation.Equals(battleReportDetails.AttackerVillageLocation); ++i)
			{
				Host.Delay(111 + i * 222);
				currentActiveVillageLocation = ReadCurrentActiveVillageLocation();
			}

			if(!currentActiveVillageLocation.Equals(battleReportDetails.AttackerVillageLocation))
			{
				/* Several users reported that switching the village failed when the chat window was open in the game:
				+ https://forum.botengine.org/t/farm-manager-tribal-wars-2-farmbot/1406/108?u=viir
				+ https://forum.botengine.org/t/farm-manager-tribal-wars-2-farmbot/1406/115?u=viir
				*/
				Host.Log("I failed to switch to the originally attacking village. I skip this report. " + switchVillageChatWindowGuide);
				goto navigateToNextReport;
			}
		}

		Host.Log("Try to find and click the button to attack again.");

		Host.Delay(555);
	
		if(!AttemptClickAndLogError(() => WaitForReference(() =>
			browserPage.XPathAsync(inReportAttackAgainButtonXPath).Result.FirstOrDefault(), 1000)))
		{
			Host.Log("I did not find the context menu button to attack again. I skip this report.");
			goto navigateToNextReport;
		}

		Host.Log("Try to find and click the button to send the attack.");

		Host.Delay(555);

		if(!AttemptClickAndLogError(() => WaitForReference(() =>
		    browserPage.XPathAsync(inSendArmyFormSendAttackButtonXPath).Result.FirstOrDefault(), 3000)))
		{
			Host.Log("Did not find button to send attack. I skip this report.");
			goto navigateToNextReport;
		}

		cycleReport.ReportsForWhichAttackHasBeenSentAgain.Add(battleReportDetails);
		sessionReport.ReportsForWhichAttackHasBeenSentAgain.Add(battleReportDetails);

		Host.Log("session_number_of_attacks_sent: " + sessionReport.ReportsForWhichAttackHasBeenSentAgain.Count);

navigateToNextReport:

		lastReportCaption = currentReportCaption ?? lastReportCaption;

		Host.Delay(1333); // Wait some time to allow browser to process the request following the click.
	
		var navigateToNextReportButton = WaitForReference(() =>
		    browserPage.XPathAsync(inReportViewNavigateToNextReportButtonXPath).Result.FirstOrDefault(), 1000);
	
		if(navigateToNextReportButton == null)
		{
		    Host.Log("Did not find the button to navigate to the next report. I stop this cycle.");
		    break;
		}
	
		var navigateToNextReportButtonClassName = navigateToNextReportButton?.GetPropertyAsync("className").Result;
	
		var navigateToNextReportButtonClassNameJsonValue = navigateToNextReportButtonClassName?.JsonValueAsync().Result;
	
		var buttonIsOrange = navigateToNextReportButtonClassNameJsonValue?.ToString()?.Contains("btn-orange");
	
		if(buttonIsOrange != true)
		{
			Host.Log("The button to navigate to the next report seems to be disabled.");
			break;
		}
	
		Host.Log("I click on the button to navigate to the next report.");
		Host.Delay(333);
		AttemptClickAndLogError(() => navigateToNextReportButton);
	
		Host.Delay(1333);
	}

	logCycleStats();

	if(cycleCount <= cycleIndex + 1)
		break;

	var breakDuration = RandomIntFromMinimumAndRandomAddition(breakBetweenCycleDurationMinSeconds, breakBetweenCycleDurationRandomAdditionMaxSeconds);

	Host.Log("I am done with this cycle. I will wait for " + (breakDuration / 60) + " minutes before continuing....");
	Host.Delay(breakDuration * 1000);
}

logSessionStats();
Host.Log("I am done with this session. I wait for one minute before terminating the script....");
Host.Delay(1000 * 60);

string ReportCaptionTextInSingleLine(string reportCaptionText) =>
	reportCaptionText?.Trim()?.Replace("\n", " - ");

struct BattleReportDetails
{
	public string Caption;

	public VillageLocation AttackerVillageLocation;

	public VillageLocation DefenderVillageLocation;

	public bool DefenderIsBarbarian;

	override public string ToString() =>
		"{ " + string.Join(" , ", new []{
			@"""AttackerVillageLocation"": """ + AttackerVillageLocation.ToString() + @"""",
			@"""DefenderVillageLocation"": """ + DefenderVillageLocation.ToString() + @"""",
			@"""DefenderIsBarbarian"": """ + DefenderIsBarbarian + @"""",
		}
		) + " }";
}

struct VillageLocation
{
	public int X, Y;

	override public string ToString() =>
		X.ToString() + "|" + Y.ToString();
}

class ReportListItem
{
    public string timeText;

    public ElementHandle htmlElement;
}

VillageLocation? ReadCurrentActiveVillageLocation()
{
	var openVillageInfoButton =
		WaitForReference(() => browserPage.XPathAsync(openVillageInfoButtonXPath).Result.FirstOrDefault(), 100);

	var parseResult = SingleVillageLocationContainedInText(GetHtmlElementInnerText(openVillageInfoButton));

	if(parseResult.IsFail)
		return null;

	return parseResult.Result;
}

ErrorStringOrGenericResult<BattleReportDetails> ParseBattleReportDetails(ElementHandle battleReportDetailsHtmlElement)
{
	try
	{
		var attackerDetails =
			battleReportDetailsHtmlElement.XPathAsync(".//table[(.//*[contains(@class, 'attack')]) and (.//*[contains(@class, 'report-village')])]").Result?.SingleOrDefault();

		var defenderDetails =
			battleReportDetailsHtmlElement.XPathAsync(".//table[(.//*[contains(@class, 'defense')]) and (.//*[contains(@class, 'report-village')])]").Result?.SingleOrDefault();

		if(attackerDetails == null)
			return Error<BattleReportDetails>("Did not find attacker details."); 

		if(defenderDetails == null)
			return Error<BattleReportDetails>("Did not find defender details."); 

		var attackerVillageLocation = VillageLocationFromReportParty(attackerDetails);

		if(attackerVillageLocation.IsFail)
			return Error<BattleReportDetails>("Failed to parse attacker village location: " + attackerVillageLocation.Error);

		var defenderCharacterInfoButton =
			defenderDetails.XPathAsync(".//*[contains(@class, 'character-info') and contains(@class, 'btn')]").Result?.FirstOrDefault();

		if(defenderCharacterInfoButton == null)
			return Error<BattleReportDetails>("Did not find defender character info button.");

		var defenderCharacterInfoButtonClass =
			defenderCharacterInfoButton?.GetPropertyAsync("className").Result?.JsonValueAsync().Result?.ToString();

		if(defenderCharacterInfoButtonClass == null)
			return Error<BattleReportDetails>("Failed to read class from defender character info button.");

		var defenderIsBarbarian = defenderCharacterInfoButtonClass?.Contains("btn-grey") ?? false;

		var defenderVillageLocation = VillageLocationFromReportParty(defenderDetails);

		if(defenderVillageLocation.IsFail)
			return Error<BattleReportDetails>("Failed to parse defender village location: " + defenderVillageLocation.Error);

		return Success(new BattleReportDetails
		{
			AttackerVillageLocation = attackerVillageLocation.Result,
			DefenderVillageLocation = defenderVillageLocation.Result,
			DefenderIsBarbarian = defenderIsBarbarian,
		});
	}
	catch(Exception e)
	{
		return Error<BattleReportDetails>("Failed with Exception: " + e.ToString());
	}
}

ErrorStringOrGenericResult<VillageLocation> VillageLocationFromReportParty(ElementHandle reportPartyHtmlElement)
{
	var village = reportPartyHtmlElement.XPathAsync(".//*[contains(@class,'report-village')]").Result.FirstOrDefault();

	if(null == village)
		return Error<VillageLocation>("Did not find village element.");

	return SingleVillageLocationContainedInText(GetHtmlElementInnerText(village)?.Trim());
}

ErrorStringOrGenericResult<VillageLocation> SingleVillageLocationContainedInText(string text)
{
	var locationMatches = System.Text.RegularExpressions.Regex.Matches(text ?? "", @"\(\s*(\d+)\s*\|s*(\d+)s*\)");

	if(locationMatches.Count != 1)
		return Error<VillageLocation>("Number of matches is " + locationMatches.Count);

	var locationMatch = locationMatches.OfType<System.Text.RegularExpressions.Match>().Single();

	if(!locationMatch.Success)
		return Error<VillageLocation>("No match of location in text: " + text);

	int locationX, locationY;

	if(!int.TryParse(locationMatch.Groups[1].Value, out locationX))
		return Error<VillageLocation>("Failed to parse locationX.");

	if(!int.TryParse(locationMatch.Groups[2].Value, out locationY))
		return Error<VillageLocation>("Failed to parse locationY.");

	return Success(new VillageLocation
	{
		X = locationX,
		Y = locationY,
	});
}

bool ReloadAndEnterReportAtTime(string reportTimeToContinueAt, int maxNumberOfAttempts = 5)
{
	Host.Log("I begin the process to restart the report UI and continue at report with time '" + reportTimeToContinueAt + "'.");

	for(var attemptNumber = 1; attemptNumber <= maxNumberOfAttempts; ++attemptNumber)
	{
		Host.Log("Attempt number " + attemptNumber + ". I close the report list.");

		for(var i = 0; i < 3; ++i)
		{
			Host.Delay(333);

			var closeWindowButton = WaitForReference(() =>
				browserPage.XPathAsync("//*[@ng-click='closeWindow()']").Result.FirstOrDefault(), 111);

			closeWindowButton?.ClickAsync().Wait();
		}

		if(!AttemptClickAndLogError(() => WaitForOpenReportListButton(1000)))
		{
			Host.Log("I did not find the button to open the report list.");
			return false;
		}

		var	pageSize = 100;

		Host.Log("I clicked the button to open the report list. Next, I set the page size to " + pageSize + ".");

		Host.Delay(3333);

		var setPageSizeButton = WaitForReference(() =>
			browserPage.XPathAsync("//*[@ng-click='setLimit(_limit)' and contains(., '" + pageSize + "')]").Result.FirstOrDefault(), 111);

		setPageSizeButton?.ClickAsync().Wait();

		Host.Delay(3333);

		Host.Log("I parse the reports in there to find the best to continue with.");

		var reports = WaitForReference(() => browserPage.XPathAsync(reportListItemXPath).Result, 1000);

		if(reports == null)
		{
			Host.Log("Did not find the report items.");
			return false;
		}

		var parsedReportItems = reports.Select(ParseReportListItem).ToList();

		Host.Log("I parsed " + parsedReportItems?.Count + " report items.");

		if(!(0 < parsedReportItems?.Count))
		{
			//	Empty report list could again be an effect of the bug in Tribal Wars 2 web app as described at https://forum.botengine.org/t/bug-in-tribal-wars-2-web-app-broken-report-display/1457, which implies that closing and opening the report list again could help.
			continue;
		}

		var	matchingReportItem =
			0 < reportTimeToContinueAt?.Length ?
			parsedReportItems.FirstOrDefault(reportItem => reportItem.timeText?.Contains(reportTimeToContinueAt) ?? false)
			: null;

		var	reportItemToContinueWith = matchingReportItem;

		if(matchingReportItem == null)
		{
			Host.Log("I did not find a report item with time of '" + reportTimeToContinueAt + "'. I continue with the last report in the list.");
			reportItemToContinueWith = parsedReportItems.LastOrDefault();
		}

		var	reportItemToContinueWithText = GetHtmlElementInnerText(reportItemToContinueWith.htmlElement);

		Host.Log("Report item to continue with: '" + ReportCaptionTextInSingleLine(reportItemToContinueWithText) + "'");

		var	parsedReportItemsUpToReportToContinueWith =
			parsedReportItems.Take(parsedReportItems.IndexOf(reportItemToContinueWith) + 1)
			.ToList();

		return OpenReportItemInReportList(parsedReportItemsUpToReportToContinueWith);
	}

	return false;
}

string GetHtmlElementInnerText(ElementHandle htmlElement) =>
	htmlElement?.GetPropertyAsync("innerText")?.Result?.JsonValueAsync()?.Result?.ToString();

bool AttemptClickAndLogError(Func<ElementHandle> getHtmlElement)
{
	//	https://github.com/GoogleChrome/puppeteer/issues/1769

	for(int attemptIndex = 0; attemptIndex < 2; ++attemptIndex)
	{
		try
		{
			var htmlElement = getHtmlElement();

			htmlElement.HoverAsync().Wait();

			Host.Delay(333);

			htmlElement.ClickAsync().Wait();

			return true;
		}
		catch(Exception e)
		{
			if(0 < attemptIndex)
				Host.Log("Failed to hover or click on attempt " + attemptIndex + " with exception:\n" + e);
		}
	}

	return false;
}

ReportListItem ParseReportListItem(ElementHandle htmlElement)
{
    var reportDateElement = htmlElement.XPathAsync(".//*[contains(@class, 'report-date')]").Result.FirstOrDefault();

    var timeText = GetHtmlElementInnerText(reportDateElement);

    return new ReportListItem
    {
        timeText = timeText,
        htmlElement = htmlElement,
    };
}

bool OpenReportItemInReportList(IReadOnlyList<ReportListItem> reportItemsUpToReportToOpen)
{
	var	reportToOpen = reportItemsUpToReportToOpen.LastOrDefault();

	var	reportItemDisplayText =
		ReportCaptionTextInSingleLine(GetHtmlElementInnerText(reportToOpen.htmlElement));

	Host.Log("I start the process to open the report '" + reportItemDisplayText + "' which is at position " + (reportItemsUpToReportToOpen.Count - 1) + " in the report list.");

	/*
	2018-08-30
	Playing around with `scrollIntoView` in the reports list, I observed that it did not work for items which are further from the current viewport.
	*/

	var	scrollStepsReportItems =
		reportItemsUpToReportToOpen
		.Where((report, i) => i % 3 == 0 || report == reportToOpen)
		.ToList();

	Host.Log("I start to scroll down....");

	var	scrollOperationsResults =
		scrollStepsReportItems
		.Select(reportItem =>
		{
			Host.Delay(111);
			var scrollResult = ScrollHtmlElementIntoViewEnd(browserPage, reportItem.htmlElement).Result;
			Host.Delay(111);
			return scrollResult;
		}).ToList();

	Host.Log("scrollOperationsResults: " + String.Join(";", scrollOperationsResults));

	if(AttemptClickAndLogError(() => reportToOpen.htmlElement))
	{
		Host.Log("Clicked on report '" + reportItemDisplayText + "'.");
		return true;
	}
	else
	{
		Host.Log("Failed to click on report '" + reportItemDisplayText + "'.");
		return false;
	}
}

ElementHandle WaitForOpenReportListButton(int timeoutMilli) =>
	WaitForReference(() =>
    {
        try
        {
            /*
            2018-08-11 Sporadically observed exception here:
            An exception of type 'System.AggregateException' occurred in System.Private.CoreLib.dll but was not handled in user code: 'One or more errors occurred.'
            Inner exceptions found, see $exception in variables window for more details.
            Innermost exception 	 PuppeteerSharp.MessageException : Protocol error (Runtime.callFunctionOn): Cannot find context with specified id 
            */
            return browserPage.XPathAsync(openReportListButtonXPath).Result.FirstOrDefault();
        }
        catch (AggregateException) // consider adding a filter here.
        {
            return null;
        }
    }, timeoutMilli);

System.Threading.Tasks.Task<string> ScrollHtmlElementIntoViewEnd(Page browserPage, ElementHandle htmlElement)
{
	return
		browserPage.EvaluateFunctionAsync<string>(
			@"(htmlElement) => htmlElement.scrollIntoView({behavior: ""instant"", block: ""end"", inline: ""nearest""})",
			htmlElement);
}

static string javascriptExpressionToGetFirstElementFromXPath(string xpath) =>
    "document.evaluate(\"" + xpath + "\", document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue";

T WaitForReference<T>(Func<T> attemptGetReference, int timeoutMilli)
    where T : class
{
    var stopwatch = Stopwatch.StartNew();

    while (true)
    {
        var reference = attemptGetReference();

        if (reference != null)
            return reference;

        if (timeoutMilli < stopwatch.ElapsedMilliseconds)
            return null;

        Host.Delay(333);
    }
}

ErrorStringOrGenericResult<T> Error<T>(string error) =>
	new ErrorStringOrGenericResult<T>{Error = error};

ErrorStringOrGenericResult<T> Success<T>(T result) =>
	new ErrorStringOrGenericResult<T>{Result = result};

struct ErrorStringOrGenericResult<T>
{
	public bool IsSuccess => Error == null;
	public bool IsFail => Error != null;

	public string Error;
	public T Result;
}

class CycleReport
{
	public Int64 BeginTime;
	readonly public List<BattleReportDetails> ReportsSeen = new List<BattleReportDetails>();
	readonly public List<BattleReportDetails> ReportsForWhichAttackHasBeenSentAgain = new List<BattleReportDetails>();

	public IEnumerable<VillageLocation> AttacksOriginVillages =>
		ReportsForWhichAttackHasBeenSentAgain.Select(report => report.AttackerVillageLocation).Distinct();

	public string StatisticsText =>
		"I have looked at " + ReportsSeen.Count +
		" reports and sent " + ReportsForWhichAttackHasBeenSentAgain.Count +
		" attacks from " + AttacksOriginVillages.Count() + " villages.";
}

int RandomIntFromMinimumAndRandomAddition(int min, int additionMax)
{
	var addition =
		additionMax < 1 ? 0 : (new Random((int)Host.GetTimeContinuousMilli()).Next() % additionMax);

	return min + addition;
}
