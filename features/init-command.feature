Feature: The init command creates the repositories for an edition
  As a user of the edition toolchain
  When I invoke the init command of the editions cli 
  I expect the program to create the repositories on GitHub for the specified edition

  Scenario: The init command aborts when no authors are specified
    When I invoke the "editions init" command
    Then the exit status should be 64
    And the output should contain "error: missing required option"

  Scenario: The init command aborts when the profile is not configured
    When I invoke the "editions init -a octocat" command without specifying a profile
    Then the exit status should be 1
    And the output should contain "error: global profile does not exist"

  @pending @credentials
  Scenario: The init command creates the repositories for the specified edition
    Given a file named ".editions-acme.yml" with:
      """
      username: opendevise-labrat
      access_token: XXXXX
      name: OpenDevise Lab Rat
      email: opendevise-labrat@users.noreply.github.com
      org: acme-magazine-01
      title: Acme Magazine
      homepage: http://acme.com/magazine
      private: false
      """
    When I invoke the command "editions -Pacme init -p 2014-03 -a octocat" interactively
    And I wait for output to contain "Create the repository acme-magazine-01/acme-2014-03-octocat for The Octocat?"
    And I type "y"
    Then the exit status should be 0
