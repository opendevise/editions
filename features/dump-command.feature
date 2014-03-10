Feature: The dump command prints the configuration for a profile
  As a user of the editions toolchain
  When I invoke the dump command of the editions cli
  I expect the program to print the configuration for the specified profile

  #@wip @announce-cmd @announce-stdout
  Scenario: The dump command warns when the profile is not configured
    When I invoke the "editions dump" command without specifying a profile
    Then the exit status should be 1
    And the output should contain "error: global profile does not exist"

  Scenario: The dump command prints the configuration for the global profile
    Given a file named ".editions.yml" with:
      """
      username: opendevise-labrat
      access_token: XXXXXX
      name: OpenDevise Lab Rat
      email: opendevise-labrat@users.noreply.github.com
      org: acme-magazine
      title: Acme Magazine
      homepage: http://acme.com/magazine
      private: false
      """
    When I invoke the "editions dump" command without specifying a profile
    Then it should pass with:
      """
      Publisher: OpenDevise Lab Rat <opendevise-labrat@users.noreply.github.com>
      Username: opendevise-labrat
      Organization: acme-magazine
      Repository Access: public
      Title: Acme Magazine
      Profile: global
      Homepage: http://acme.com/magazine
      """

  Scenario: The dump command warns when the profile is not configured
    When I invoke the "editions dump" command with the profile "acme"
    Then the exit status should be 1
    And the output should contain "error: acme profile does not exist"

  Scenario: The dump command prints the configuration for the specified profile
    Given a file named ".editions-acme.yml" with:
      """
      username: opendevise-labrat
      access_token: XXXXXX
      name: OpenDevise Lab Rat
      email: opendevise-labrat@users.noreply.github.com
      org: acme-magazine
      title: Acme Magazine
      homepage: http://acme.com/magazine
      private: false
      """
    When I invoke the "editions dump" command with the profile "acme"
    Then it should pass with:
      """
      Publisher: OpenDevise Lab Rat <opendevise-labrat@users.noreply.github.com>
      Username: opendevise-labrat
      Organization: acme-magazine
      Repository Access: public
      Title: Acme Magazine
      Profile: acme
      Homepage: http://acme.com/magazine
      """
