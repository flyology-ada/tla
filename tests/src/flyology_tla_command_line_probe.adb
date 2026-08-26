with Ada.Exceptions;
with Flyology_TLA.Command_Line;
with Flyology_TLA.Replay;
with Flyology_TLA.Traces;

procedure Flyology_TLA_Command_Line_Probe is

   Default_Limits : constant Flyology_TLA.Traces.Load_Limits :=
     (Maximum_File_Bytes   => 100_000,
      Maximum_Steps        => 10,
      Maximum_JSON_Depth   => 20,
      Maximum_Object_Names => 1_000,
      Maximum_Name_Bytes   => 1_000,
      Maximum_String_Bytes => 10_000,
      Maximum_Value_Bytes  => 50_000);

   Flags : Flyology_TLA.Command_Line.Application_Flag_Array :=
     [1 => Flyology_TLA.Command_Line.Flag
       ("--probe", "exercise a consumer-defined boolean flag")];

begin
   declare
      Config : Flyology_TLA.Command_Line.Configuration :=
        Flyology_TLA.Command_Line.Parse (Default_Limits, Flags);
   begin
      if Flyology_TLA.Command_Line.Help_Requested (Config) then
         Flyology_TLA.Command_Line.Put_Help (Flags);
         return;
      end if;

      declare
         Trace  : constant Flyology_TLA.Traces.Trace :=
           Flyology_TLA.Command_Line.Load (Config);
         Result : constant Flyology_TLA.Replay.Replay_Result :=
           (Status         => Flyology_TLA.Replay.Conformant,
            Compared_Steps => Natural (Trace.Steps.Length),
            Failure_Step   => 0,
            Property_Name  => <>,
            Fingerprint    => <>,
            Detail         => <>);
      begin
         if Flyology_TLA.Command_Line.Is_Set (Flags (1))
           and then Result.Compared_Steps /= 2
         then
            raise Program_Error with "consumer flag probe saw an unexpected trace";
         end if;
         Flyology_TLA.Command_Line.Report (Config, Result);
         Flyology_TLA.Command_Line.Set_Exit_Status (Result);
      end;
   end;
exception
   when Error : Flyology_TLA.Command_Line.Usage_Error =>
      Flyology_TLA.Command_Line.Fail
        (Ada.Exceptions.Exception_Message (Error), Flags, Show_Help => True);
   when Error : Flyology_TLA.Traces.Trace_Error =>
      Flyology_TLA.Command_Line.Fail
        ("cannot load trace: " & Ada.Exceptions.Exception_Message (Error));
end Flyology_TLA_Command_Line_Probe;
