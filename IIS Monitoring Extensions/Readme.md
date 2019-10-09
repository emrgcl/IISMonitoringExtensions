https://docs.microsoft.com/en-us/previous-versions/system-center/developer/ee692976%28v%3dmsdn.10%29

The DaysOfWeekMask element represents the days that the module should trigger output. A single day or multiple days can be specified according to the values listed in the following table.


| Day             | Value |
|-----------------|-------|
| Sunday          | 1     |
| Monday          | 2     |
| Tuesday         | 4     |
| Wednesday       | 8     | 
| Thursday        | 16    |
| Friday          | 32    |
| Saturday        | 62    |

To specify a single day, enter the enumerator value for that day directly into the DaysOfWeekMask configuration element.

To specify multiple days, add the enumerator values for the days together. For example, for Monday, Wednesday, and Friday, specify 42 (2+8+32).

 # TODO

  - Add Override Documentation as dispaly strings to IIS.Monitoring.Extensions.WriteAction.ArchiveIISLogs
  - Add Override Documentation as dispaly strings to IIS.Monitoring.Extensions.ProbeAction.ArchiveIISLogs
  - Add Rule
    ```xml
          <Rule ID="MomUIGeneratedRule8653a9f82b1f483e845866a2711c3e08" Enabled="false" Target="MicrosoftWindowsLibrary7585010!Microsoft.Windows.Server.OperatingSystem" ConfirmDelivery="false" Remotable="true" Priority="Normal" DiscardLevel="100">
        <Category>Custom</Category>
        <DataSources>
          <DataSource ID="Scheduler" TypeID="System!System.Scheduler">
            <Scheduler>
              <WeeklySchedule>
                <Windows>
                  <Daily>
                    <Start>00:00</Start>
                    <End>02:00</End>
                    <DaysOfWeekMask>127</DaysOfWeekMask>
                  </Daily>
                </Windows>
              </WeeklySchedule>
              <ExcludeDates />
            </Scheduler>
          </DataSource>
        </DataSources>
        <WriteActions>
          <WriteAction ID="ExecuteScript" TypeID="MicrosoftWindowsLibrary7585010!Microsoft.Windows.ScriptWriteAction">
            <ScriptName>Test.vbs</ScriptName>
            <Arguments>Paramter1=45545454</Arguments>
            <ScriptBody>script is here</ScriptBody>
            <TimeoutSeconds>60</TimeoutSeconds>
          </WriteAction>
        </WriteActions>
      </Rule>
    ```
    - add Task
    ```xml
          <Task ID="ConsoleTaskGeneratedByUI757af9c8f8424a858e5a2fd5d631c817" Accessibility="Public" Enabled="true" Target="MicrosoftWindowsLibrary7585010!Microsoft.Windows.Computer" Timeout="300" Remotable="true">
        <Category>Custom</Category>
        <WriteAction ID="PA" TypeID="MicrosoftWindowsLibrary7585010!Microsoft.Windows.ScriptWriteAction">
          <ScriptName>test.vbs</ScriptName>
          <Arguments />
          <ScriptBody>hedehodo</ScriptBody>
          <TimeoutSeconds>60</TimeoutSeconds>
        </WriteAction>
      </Task>
    </Tasks>
    ```
    - add secure reference to probe and write action modules
    ```xml
     <ProbeActionModuleType ID="Microsoft.SQLServer.2012.VerifyWindowsServiceState" Accessibility="Internal" RunAs="SQL!Microsoft.SQLServer.SQLProbeAccount">
      <TypeDefinitions>
      <SecureReferences>
      <SecureReference ID="Microsoft.SQLServer.SQLDefaultAccount" Accessibility="Public" Context="System!System.Entity" />
      <SecureReference ID="Microsoft.SQLServer.SQLProbeAccount" Accessibility="Public" Context="System!System.Entity" />
      <SecureReference ID="Microsoft.SQLServer.SQLDiscoveryAccount" Accessibility="Public" Context="System!System.Entity" />
      </SecureReferences>
      </TypeDefinitions>
      <DisplayString ElementID="Microsoft.SQLServer.SQLProbeAccount">
      <Name>SQL Server Monitoring Account</Name>
      <Description>This account is used for monitoring of SQL Server 2008, 2008 R2 and 2012.</Description>
      </DisplayString>
    ```
    - add maml documentation
    ```xml
    <KnowledgeArticle ElementID="Microsoft.SQLServer.Library.AlertsScopeGroupDiscovery" Visible="true">
      <MamlContent>
        <maml:section xmlns:maml="http://schemas.microsoft.com/maml/2004/10">
          <maml:title>Summary</maml:title>
          <maml:para>This object discovery populates the Alerts Scope group to contain all SQL Server Roles.</maml:para>
        </maml:section>
        <maml:section xmlns:maml="http://schemas.microsoft.com/maml/2004/10">
          <maml:title>Overridable Parameters</maml:title>
          <maml:table>
            <maml:row>
              <maml:entry>
                <maml:para>Name</maml:para>
              </maml:entry>
              <maml:entry>
                <maml:para>Description</maml:para>
              </maml:entry>
              <maml:entry>
                <maml:para>Default Value</maml:para>
              </maml:entry>
            </maml:row>
            <maml:row>
              <maml:entry>
                <maml:para>Enabled</maml:para>
              </maml:entry>
              <maml:entry>
                <maml:para>Enables or disables the workflow.</maml:para>
              </maml:entry>
              <maml:entry>
                <maml:para>Yes</maml:para>
              </maml:entry>
            </maml:row>
          </maml:table>
        </maml:section>
      </MamlContent>
    </KnowledgeArticle>
    ```
    
