with Ada.Exceptions;
with Ada.Strings.Unbounded;
with Counter_Model;
with Flyology_TLA.Command_Line;
with Flyology_TLA.Replay;
with Flyology_TLA.Traces;

procedure Counter_Conformance is

   use Ada.Strings.Unbounded;
   use type Counter_Model.State_Count_Type;

   Limits : constant Flyology_TLA.Traces.Load_Limits :=
     (Maximum_File_Bytes   => 1_000_000,
      Maximum_Steps        => 1_000,
      Maximum_JSON_Depth   => 64,
      Maximum_Object_Names => 10_000,
      Maximum_Name_Bytes   => 4_096,
      Maximum_String_Bytes => 100_000,
      Maximum_Value_Bytes  => 500_000);

   --  Counter_Model is generated from Counter.tla. Extending its Adapter is
   --  the only model-specific integration step; this file never handles JSON.
   type Counter_Adapter is new Counter_Model.Adapter with record
      Buggy   : Boolean := False;
      Current : Counter_Model.State_Type :=
        (Count       => 0,
         Last_Action => Counter_Model.State_Last_Action_Init);
   end record;

   overriding procedure Reset
     (Self     : in out Counter_Adapter;
      Observed : out Counter_Model.State_Type;
      Status   : out Flyology_TLA.Replay.Adapter_Outcome);

   overriding procedure Apply
     (Self         : in out Counter_Adapter;
      Index        : Positive;
      Action       : String;
      Role         : String;
      Input        : Counter_Model.Input_Type;
      Model_Source : String;
      Observed     : out Counter_Model.Outcome_Type;
      State        : out Counter_Model.State_Type;
      Status       : out Flyology_TLA.Replay.Adapter_Outcome);

   procedure Reset
     (Self     : in out Counter_Adapter;
      Observed : out Counter_Model.State_Type;
      Status   : out Flyology_TLA.Replay.Adapter_Outcome)
   is
   begin
      --  Reset establishes the same semantic boundary as the TLA+ Init action
      --  and returns the complete generated state record for comparison.
      Self.Current :=
        (Count       => 0,
         Last_Action => Counter_Model.State_Last_Action_Init);
      Observed := Self.Current;
      Status := (Succeeded => True, Detail => Null_Unbounded_String);
   end Reset;

   procedure Apply
     (Self         : in out Counter_Adapter;
      Index        : Positive;
      Action       : String;
      Role         : String;
      Input        : Counter_Model.Input_Type;
      Model_Source : String;
      Observed     : out Counter_Model.Outcome_Type;
      State        : out Counter_Model.State_Type;
      Status       : out Flyology_TLA.Replay.Adapter_Outcome)
   is
      pragma Unreferenced (Index, Input);
   begin
      --  Action metadata remains textual because it names model operators.
      --  Input is already decoded and range-checked by the generated bridge.
      if Action /= "Counter!Increment"
        or else Role /= "increment"
        or else Model_Source /= "Counter!Increment"
      then
         Observed := (Accepted => False);
         State := Self.Current;
         Status :=
           (Succeeded => False,
            Detail    => To_Unbounded_String ("unsupported modeled action or input"));
         return;
      end if;

      --  Execute exactly one implementation transition. Only observations
      --  are returned; the expected model outcome/state are never provided.
      --  The optional demonstration bug loses the modeled increment. The
      --  adapter still reports its honest state, allowing replay to expose
      --  the discrepancy instead of manufacturing a failure response.
      if not Self.Buggy then
         Self.Current.Count := Self.Current.Count + 1;
      end if;
      Self.Current.Last_Action := Counter_Model.State_Last_Action_Increment;
      Observed := (Accepted => True);
      State := Self.Current;
      Status := (Succeeded => True, Detail => Null_Unbounded_String);
   end Apply;

   Flags : Flyology_TLA.Command_Line.Application_Flag_Array :=
     [1 => Flyology_TLA.Command_Line.Flag
       ("--buggy", "run the example with an intentional lost-update bug")];

begin
   declare
      Config : Flyology_TLA.Command_Line.Configuration :=
        Flyology_TLA.Command_Line.Parse (Limits, Flags);
   begin
      if Flyology_TLA.Command_Line.Help_Requested (Config) then
         Flyology_TLA.Command_Line.Put_Help (Flags);
         return;
      end if;

      declare
         Trace   : constant Flyology_TLA.Traces.Trace :=
           Flyology_TLA.Command_Line.Load (Config);
         Adapter : Counter_Adapter;
         Result  : Flyology_TLA.Replay.Replay_Result;
      begin
         Adapter.Buggy := Flyology_TLA.Command_Line.Is_Set (Flags (1));

         --  Generated Run translates the typed observations internally and
         --  delegates structural comparison to the reusable replay engine.
         Counter_Model.Run
           (Adapter,
            Trace,
            Flyology_TLA.Command_Line.Limits (Config),
            Result);
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
end Counter_Conformance;
