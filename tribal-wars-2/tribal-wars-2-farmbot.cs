/* Tribal Wars 2 Farmbot v2018-08-20
This bot goes through the list of reports to attack again.
Farming is done following the process outlined at https://forum.botengine.org/t/tribal-wars-2-farmbot-2018/1330
*/

using System;
using System.Diagnostics;
using System.Linq;
using PuppeteerSharp;
using System.Collections.Generic;


const int waitForReportListButtonTimespanMaxSeconds = 120;
const int inGameDelaySeconds = 10;
const int cycleDurationMax = 60 * 30;


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

static string openVillageInfoButtonXPath => "//*[@ng-click='openVillageInfo(character.getSelectedVillage().getId())']";

static string reportJumpToAttackerVillageXPath => "//*[starts-with(@ng-click, 'jumpToVillage(report[type].attVillage')]";

static string mapVillageContextMenuItemActivateXPath => "//*[contains(@class, 'context-menu-item') and contains(@class, 'activate')]";

var browserPage = WebBrowser.OpenNewBrowserPage();

browserPage.SetViewportAsync(new ViewPortOptions { Width = 1112, Height = 706, }).Wait();

Host.Log("Looks like opening the web browser was successful.");

var waitForReportListButtonStopwatch = Stopwatch.StartNew();

while(true)
{
	Host.Log("I did not find the button to open the report list. Maybe the game is still loading. (The location of the current page is '" + browserPage.Url + "').");
	Host.Log("If you have not done this yet, please log in and enter the game in the web browser I opened when the script started. For now, I keep looking for that button to appear....");

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
Host.Log("Please configure filtering in the reports list now. I will wait for " + inGameDelaySeconds + " seconds before continuing. In case you need more time to configure the game, you can pause the bot");

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
	throw new NotImplementedException("Did not find button to switch to battle reports.");

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

AttemptClickAndLogError(() => parsedReportItems.FirstOrDefault().linkToReport);

var reportsSeen = new List<BattleReportDetails>();
var reportsForWhichAttackHasBeenSentAgain = new List<BattleReportDetails>();

var cycleBeginTime = Host.GetTimeContinuousMilli() / 1000;

while(true)
{
	var cycleDuration = Host.GetTimeContinuousMilli() / 1000 - cycleBeginTime;

	if(cycleDurationMax < cycleDuration)
	{
		Host.Log("Stopping after " + cycleDuration + " seconds for safety.");
		break;
	}

	Host.Delay(1333);

	var currentReportHeader = WaitForReference(() =>
		browserPage.XPathAsync("//div[contains(@class,'report-header-wrapper')]").Result?.FirstOrDefault(), 333);

	var currentReportCaption =
		GetHtmlElementInnerText(currentReportHeader)?.Trim();

	Host.Log("Caption of the current open report:\n" + currentReportCaption?.Replace("\n", " - "));

	var battleReportDetailsContainer =
		WaitForReference(() => browserPage.XPathAsync(inBattleReportViewDetailsXPath).Result.FirstOrDefault(), 333);

	if(battleReportDetailsContainer == null)
	{
		Host.Log("Did not find details container in battle report. Maybe this is a different kind of report, so I continue with the next report.");
		goto navigateToNextReport;
	}

	var battleReportDetailsContainerClass =
		battleReportDetailsContainer?.GetPropertyAsync("className").Result?.JsonValueAsync().Result?.ToString();

	Host.Log("Inspect battleReportDetailsContainerClass: " + battleReportDetailsContainerClass);

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
		Host.Log("Failed to parse the battle report details (" + parseBattleReportDetails.Error + "). I end this cycle.");
		break;
	}

	var	battleReportDetails = parseBattleReportDetails.Result;

	Host.Log("Battle report details:\n" + battleReportDetails);

	reportsSeen.Add(battleReportDetails);

	if(reportsForWhichAttackHasBeenSentAgain.Any(report =>
		report.AttackerVillageLocation.Equals(battleReportDetails.AttackerVillageLocation) &&
		report.DefenderVillageLocation.Equals(battleReportDetails.DefenderVillageLocation)))
	{
		Host.Log("An attack from " + battleReportDetails.AttackerVillageLocation + " to " + battleReportDetails.DefenderVillageLocation + " has already been sent in this cycle. I skip this one and continue with the next report");
		goto navigateToNextReport;
	}

	var currentActiveVillageLocation = ReadCurrentActiveVillageLocation();

	if(!currentActiveVillageLocation.HasValue)
	{
		Host.Log("Failed to read the current active village location. I stop this cycle.");
		break;
	}

	Host.Log("Current active village location is " + currentActiveVillageLocation);

	if(!currentActiveVillageLocation.Equals(battleReportDetails.AttackerVillageLocation))
	{
		Host.Log("Switching to village " + battleReportDetails.AttackerVillageLocation + ".");

		if(!AttemptClickAndLogError(() =>
			WaitForReference(() => browserPage.XPathAsync(reportJumpToAttackerVillageXPath).Result.FirstOrDefault(), 400)))
		{
			Host.Log("I did not find the button to jump to attackers village. I skip this report.");
			goto navigateToNextReport;
		}

		Host.Delay(1777);

		if(!AttemptClickAndLogError(() => WaitForReference(() =>
			browserPage.XPathAsync(mapVillageContextMenuItemActivateXPath).Result.FirstOrDefault(), 3333)))
		{
			Host.Log("I did not find the context menu button to activate the village. I skip this report.");
			goto navigateToNextReport;
		}

		Host.Delay(1333);

		currentActiveVillageLocation = ReadCurrentActiveVillageLocation();

		if(!currentActiveVillageLocation.Equals(battleReportDetails.AttackerVillageLocation))
		{
			Host.Log("I failed to switch to the originally attacking village. I skip this report.");
			goto navigateToNextReport;
		}
	}

	Host.Log("Try to find and click the button to attack again.");

	Host.Delay(555);

	if(!AttemptClickAndLogError(() => WaitForReference(() =>
		browserPage.XPathAsync(inReportAttackAgainButtonXPath).Result.FirstOrDefault(), 4000)))
		throw new NotImplementedException("Did not find button to attack again.");

	Host.Log("Try to find and click the button to send the attack.");

	Host.Delay(555);

	if(!AttemptClickAndLogError(() => WaitForReference(() =>
	    browserPage.XPathAsync(inSendArmyFormSendAttackButtonXPath).Result.FirstOrDefault(), 4000)))
	    throw new NotImplementedException("Did not find button to send attack.");

	reportsForWhichAttackHasBeenSentAgain.Add(battleReportDetails);

	Host.Log("cycle_number_of_attacks_sent: " + reportsForWhichAttackHasBeenSentAgain.Count);

navigateToNextReport:

	Host.Delay(1333); // Wait some time to allow browser to process the request following the click.

	var navigateToNextReportButton = WaitForReference(() =>
	    browserPage.XPathAsync(inReportViewNavigateToNextReportButtonXPath).Result.FirstOrDefault(), 1000);

	if(navigateToNextReportButton == null)
	{
	    Host.Log("Did not find button to navigate to next report.");
	    break;
	}

	var navigateToNextReportButtonClassName = navigateToNextReportButton?.GetPropertyAsync("className").Result;

	var navigateToNextReportButtonClassNameJsonValue = navigateToNextReportButtonClassName?.JsonValueAsync().Result;

	Host.Log("navigateToNextReportButtonClassName.jsonValue: " + navigateToNextReportButtonClassNameJsonValue);

	var buttonIsOrange = navigateToNextReportButtonClassNameJsonValue?.ToString()?.Contains("btn-orange");

	if(buttonIsOrange != true)
	{
		Host.Log("Button to navigate to next report seems to be disabled.");
		break;
	}

	Host.Log("I click on the button to navigate to next report.");
	Host.Delay(333);
	AttemptClickAndLogError(() => navigateToNextReportButton);

	Host.Delay(1333);
}

var attacksOriginVillages =
	reportsForWhichAttackHasBeenSentAgain.Select(report => report.AttackerVillageLocation).Distinct().ToList();

Host.Log("I have looked at " + reportsSeen.Count +
	" reports and sent " + reportsForWhichAttackHasBeenSentAgain.Count +
	" attacks from " + attacksOriginVillages.Count + " villages.");

Host.Log("I am done for now. I wait for one minute before terminating the script....");
Host.Delay(1000 * 60);

struct BattleReportDetails
{
	public VillageLocation AttackerVillageLocation;

	public VillageLocation DefenderVillageLocation;

	override public string ToString() =>
		"{ " + string.Join(" , ", new []{
			@"""AttackerVillageLocation"": """ + AttackerVillageLocation.ToString() + @"""",
			@"""DefenderVillageLocation"": """ + DefenderVillageLocation.ToString() + @"""",
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

    public ElementHandle linkToReport;
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
	var attackerDetails =
		battleReportDetailsHtmlElement.XPathAsync(".//table[.//*[contains(@class, 'attack')]]").Result?.SingleOrDefault();

	var defenderDetails =
		battleReportDetailsHtmlElement.XPathAsync(".//table[.//*[contains(@class, 'defense')]]").Result?.SingleOrDefault();

	if(attackerDetails == null)
		return Error<BattleReportDetails>("Did not find attacker details."); 

	if(defenderDetails == null)
		return Error<BattleReportDetails>("Did not find defender details."); 

	var attackerVillageLocation = VillageLocationFromReportParty(attackerDetails);

	if(attackerVillageLocation.IsFail)
		return Error<BattleReportDetails>("Failed to parse attacker village location: " + attackerVillageLocation.Error);

	var defenderVillageLocation = VillageLocationFromReportParty(defenderDetails);

	if(defenderVillageLocation.IsFail)
		return Error<BattleReportDetails>("Failed to parse defender village location: " + defenderVillageLocation.Error);

	return Success(new BattleReportDetails
	{
		AttackerVillageLocation = attackerVillageLocation.Result,
		DefenderVillageLocation = defenderVillageLocation.Result,
	});
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

    var linkToReport = htmlElement;

    return new ReportListItem
    {
        timeText = timeText,
        linkToReport = linkToReport,
    };
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
