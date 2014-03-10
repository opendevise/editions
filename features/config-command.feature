Feature: The config command populates a configuration file
  As a user of the edition toolchain
  When I invoke the config command of the editions cli 
  I expect the program to populate a configuration file for the specified profile

  Scenario: The config command should warn if the username is empty
    When I invoke the "editions config -u '' -t 'Acme Magazine' -h 'http://acme.com/magazine'" command
    Then the exit status should be 64
    And the output should contain "username cannot be empty"
    And a file named ".editions.yml" should not exist

  @pending @credentials
  Scenario: The config command populates the configuration file for the global profile
    When I invoke the command "editions config -u EDITIONS_USERNAME -t 'Acme Magazine' -h 'http://acme.com/magazine'" interactively
    And I wait for output to contain "Enter the GitHub password"
    And I type the text from the environment variable "EDITIONS_PASSWORD"
    Then the exit status should be 0
    And a file named ".editions.yml" should exist
