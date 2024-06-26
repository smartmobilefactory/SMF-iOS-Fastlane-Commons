@echo off
rem This script makes it easier to manage cli version, user, and password settings for various CLIs
rem Customize this for your installation. Be careful on upgrades or rename it to something else.
rem
rem Examples:
rem     atlassian confluence --action getServerInfo
rem     atlassian jira --action getServerInfo
rem     atlassian myOtherConfluence --action getServerInfo
rem
rem Use /s as the first parameter when calling this from a script for proper error handling
rem Examples:
rem     altassian /s confluence --action getServerInfo

rem Use SETLOCAL to make all variables settings local to this file only
rem Use ENABLEDELAYEDEXPANSION to enable !xxxx! expansion on execution in the for loop
rem SHIFT is used to shift the parameters over 1 so logic is similar even if /s is used

SETLOCAL ENABLEDELAYEDEXPANSION

rem - - - - - - - - - - - - - - - - - - - - START CUSTOMIZE FOR YOUR INSTALLATION !!!
set user=automation
set password=automation
rem - - - - - - - - - - - - - - - - - - - - - END CUSTOMIZE FOR YOUR INSTALLATION !!!

rem remember this command so that script can be run from any directory location
set command=%0
rem remember the directory path to this bat file
set dirPath=%~dp0

rem need to reverse windows names to posix names by changing \ to /
set dirPath=%dirPath:\=/%
rem remove blank at end of string
set dirPath=%dirPath:~0,-1%

rem Keep track of parameters, could be with or without /s parameter
set parameterIndex=1
if NOT "%1"=="/s" (set flag=/B) else (SHIFT && set /a parameterIndex-=1)

set application=%1

rem - - - - - - - - - - - - - - - - - - - - START CUSTOMIZE FOR YOUR INSTALLATION !!!
if "%application%"=="confluence"  set string=confluence-cli-7.8.0.jar --server https://confluence.examplegear.com --user %user% --password %password%
if "%application%"=="jira"        set string=jira-cli-7.8.0.jar --server https://jira.examplegear.com --user %user% --password %password%
if "%application%"=="agile"       set string=agile-cli-7.8.0.jar --server https://jira.examplegear.com --user %user% --password %password%
if "%application%"=="servicedesk" set string=servicedesk-cli-7.8.0.jar --server https://jira.examplegear.com --user %user% --password %password%
if "%application%"=="tempo"       set string=tempo-cli-7.8.0.jar --server https://jira.examplegear.com --user %user% --password %password%
if "%application%"=="structure"   set string=structure-cli-7.8.0.jar --server https://jira.examplegear.com --user %user% --password %password%
if "%application%"=="bamboo"      set string=bamboo-cli-7.8.0.jar --server https://bamboo.examplegear.com --user %user% --password %password%
if "%application%"=="bitbucket"   set string=bitbucket-cli-7.8.0.jar --server https://bitbucket.examplegear.com --user %user% --password %password%
if "%application%"=="hipchat"     set string=hipchat-cli-7.8.0.jar --server https://hipchat.examplegear.com --token xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
if "%application%"=="trello"      set string=trello-cli-7.8.0.jar --token xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
if "%application%"=="upm"         set string=upm-cli-7.8.0.jar --server https://bitbucket.examplegear.com --user %user% --password %password%
if "%application%"=="csv"         set string=csv-cli-7.8.0.jar --server https://bitbucket.examplegear.com --user %user% --password %password%
if "%application%"=="all"         set string=all-cli-7.8.0.jar
rem - - - - - - - - - - - - - - - - - - - - - END CUSTOMIZE FOR YOUR INSTALLATION !!!

rem get all the remaining parameters
for %%A in (%*) do (
    if !parameterIndex! geq 2 set params=!params! %%A
    set /a parameterIndex+=1
)

rem Report an error if application is not found in the list
if "%application%"=="" (echo Missing application parameter. Specify an application like confluence, jira, or similar. && EXIT %flag% -99)
if "%string%"=="" (echo Application %application% not found in %command% && EXIT %flag% -99)

rem echo Params: %params%
rem echo Command: "%dirPath%"/lib/%string% %params%

java -jar "%dirPath%"/lib/%string% %params%

rem Exit with the correct error level.
rem Use /B if run from command line, so it keeps the command line
rem Use nothing if run from script so that the script gets the proper error level returned to it

EXIT %flag% %ERRORLEVEL%

