Feature: The cli is alive
  As a user of the editions toolchain
  I expect the editions cli to load successfully
  So I can call its commands

  #@wip @announce-cmd @announce-stdout
  Scenario: The cli responds to the help command
    When I invoke the "editions help" command
    Then the exit status should be 0
    And the output should contain "GLOBAL OPTIONS"
    And the output should match /GLOBAL OPTIONS$.*--help *- Show this message/
    And the output should contain "COMMANDS"
    And the output should match /COMMANDS$.*$\s*help *- Shows a list of commands/

  Scenario: The cli responds to the global -h flag
    When I invoke the "editions -h" command
    Then the exit status should be 0
    And the output should contain "GLOBAL OPTIONS"
    And the output should match /GLOBAL OPTIONS$.*--help *- Show this message/
    And the output should contain "COMMANDS"
    And the output should match /COMMANDS$.*$\s*help *- Shows a list of commands/

  Scenario: The cli runs the help command by default
    When I invoke the "editions" command
    Then the exit status should be 0
    And the output should contain "GLOBAL OPTIONS"
    And the output should match /GLOBAL OPTIONS$.*--help *- Show this message/
    And the output should contain "COMMANDS"
    And the output should match /COMMANDS$.*$\s*help *- Shows a list of commands/
