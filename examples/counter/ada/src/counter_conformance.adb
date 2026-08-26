with Ada.Command_Line;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Counter_Model;
with Flyology_TLA.Replay;
with Flyology_TLA.Traces;

procedure Counter_Conformance is

   use Ada.Strings.Unbounded;
   use type Counter_Model.State_Count_Type;
   use type Flyology_TLA.Replay.Verdict;

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
      Self.Current.Count := Self.Current.Count + 1;
      Self.Current.Last_Action := Counter_Model.State_Last_Action_Increment;
      Observed := (Accepted => True);
      State := Self.Current;
      Status := (Succeeded => True, Detail => Null_Unbounded_String);
   end Apply;

   Trace   : constant Flyology_TLA.Traces.Trace :=
     Flyology_TLA.Traces.Load (Ada.Command_Line.Argument (1), Limits);
   Adapter : Counter_Adapter;
   Result  : Flyology_TLA.Replay.Replay_Result;

begin
   --  Generated Run translates the typed observations internally and then
   --  delegates structural comparison and first-divergence reporting to the
   --  reusable Flyology_TLA replay engine.
   Counter_Model.Run (Adapter, Trace, Limits, Result);
   if Result.Status = Flyology_TLA.Replay.Conformant then
      Ada.Text_IO.Put_Line
        ("conformant:" & Natural'Image (Result.Compared_Steps) & " modeled steps");
   else
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         Flyology_TLA.Replay.Verdict'Image (Result.Status)
         & " at step"
         & Natural'Image (Result.Failure_Step)
         & ": "
         & To_String (Result.Fingerprint)
         & " — "
         & To_String (Result.Detail));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Counter_Conformance;
