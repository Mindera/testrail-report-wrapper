# testrail-report-wrapper
The testrail-report-wrapper enables in a very simple way to automatically import results to Testrail, using the reports of any test automation framework
## Requirements

## Dependencies
Because Cucumber reports doesn’t have the result for each outline scenario, please use the following project:
https://gist.github.com/blt04/9866357
Please notice that you need to generate the report with a new command line:
```
$ cucumber --format Cucumber::Formatter::JsonExpanded --out results.json features
````

## Automation framework Parser's
* Cucumber

## Install
1. Download the software project:
2. If you are using cucumber with Scenario Outline, download the following file from (https://gist.github.com/blt04/9866357) and place it into features/support


## How to use
In a few steps:

1. Create the Results object - Load any file into memory.
2. Create the Wrapper object - Test Plan name and Project name is needed.
3. Create a run for each configuration needed, indicating the parser you need and the configuration.
4. Create the Plan entry
5. Set the results


```
> results_iPadMini_phy_IOS8 = TestRailReporterWrapper::Results.new('../iPadMini_phy_IOS8.json')
> results_iPad2_sim_IOS7 = TestRailReporterWrapper::Results.new('../iPhone5s_phy_IOS7.json')
> support = TestRailReporterWrapper::ReporterWrapper.new('Automatic Tests', 'MY_PROJECT')
> support.delete_plan_entry('build 636')
> support.add_run(results_iPadMini_phy_IOS8.cucumber_parse, ['iPad mini', 'Physical', 'IOS 8'])
> support.add_run(results_iPad2_sim_IOS7.cucumber_parse, ['iPad 2', 'Physical', 'IOS 7'])
> support.create_plan_entry('build 636')
> support.set_results
```
