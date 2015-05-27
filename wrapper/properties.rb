TR_CLIENT = 'https://<client>.testrail.net'
TR_USER = '<user>'
TR_PASSWORD = '<pwd>'

TR_PROJECT_NAME = '<project>'

TR_SYS_CONFIGS_TYPE = 'custom_configurations'

# This Hash maps the results of the json file with the available Test Rail result status.
# This id's are configured under Administration > Customizations > Status
# Change this values if necessary
TR_MEM_RESULT_STATUS = {
    PASSED: 1,
    UNTESTED: 3,
    FAILED: 5,
    SKIPPED: 6,
}

# This id's are configured under Administration > Customizations > Test Case Type
# Change this values if necessary
TR_CASE_TYPES = {
    AUTOMATED: 1,
    FUNCTIONALITY: 2,
    PERFORMANCE: 3,
    MANUAL:7
}
