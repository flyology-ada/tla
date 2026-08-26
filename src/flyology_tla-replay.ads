with Ada.Strings.Unbounded;
with Flyology_TLA.Traces;

package Flyology_TLA.Replay is

   type Adapter is abstract tagged limited null record;

   type Replay_Command is record
      Index        : Positive;
      Action       : Ada.Strings.Unbounded.Unbounded_String;
      Role         : Ada.Strings.Unbounded.Unbounded_String;
      Input_JSON   : Ada.Strings.Unbounded.Unbounded_String;
      Model_Source : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   type Adapter_Outcome is record
      Succeeded : Boolean := False;
      Detail    : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   procedure Reset
     (Self                : in out Adapter;
      Observed_State_JSON : out Ada.Strings.Unbounded.Unbounded_String;
      Outcome             : out Adapter_Outcome)
   is abstract;

   procedure Apply
     (Self                  : in out Adapter;
      Command               : Replay_Command;
      Observed_Outcome_JSON : out Ada.Strings.Unbounded.Unbounded_String;
      Observed_State_JSON   : out Ada.Strings.Unbounded.Unbounded_String;
      Outcome               : out Adapter_Outcome)
   is abstract;

   type Comparison is record
      Equivalent  : Boolean := False;
      Fingerprint : Ada.Strings.Unbounded.Unbounded_String;
      Detail      : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   procedure Compare_Initial_State
     (Self          : in out Adapter;
      Expected_JSON : String;
      Observed_JSON : String;
      Limits        : Flyology_TLA.Traces.Load_Limits;
      Result        : out Comparison);

   procedure Compare_Step
     (Self                  : in out Adapter;
      Command               : Replay_Command;
      Expected_Outcome_JSON : String;
      Expected_State_JSON   : String;
      Observed_Outcome_JSON : String;
      Observed_State_JSON   : String;
      Limits                : Flyology_TLA.Traces.Load_Limits;
      Result                : out Comparison);

   type Verdict is (Conformant, Diverged, Adapter_Error, Invalid_Trace);

   type Replay_Result is record
      Status         : Verdict := Adapter_Error;
      Compared_Steps : Natural := 0;
      Failure_Step   : Natural := 0;
      Property_Name  : Ada.Strings.Unbounded.Unbounded_String;
      Fingerprint    : Ada.Strings.Unbounded.Unbounded_String;
      Detail         : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   type Observation_Kind is
     (No_Observation, Initial_State_Observation, Step_Observation);

   type Observed_Comparison
     (Kind : Observation_Kind := No_Observation) is private;

   type Replay_Result_V2 is record
      Summary  : Replay_Result;
      Observed : Observed_Comparison;
   end record;

   function To_Version_2 (Summary : Replay_Result) return Replay_Result_V2;
   function With_Initial_Observation
     (Summary             : Replay_Result;
      Observed_State_JSON : String;
      Limits              : Flyology_TLA.Traces.Load_Limits) return Replay_Result_V2;
   function With_Step_Observation
     (Summary               : Replay_Result;
      Observed_Outcome_JSON : String;
      Observed_State_JSON   : String;
      Limits                : Flyology_TLA.Traces.Load_Limits) return Replay_Result_V2;

   function Outcome_JSON (Item : Observed_Comparison) return String;
   function State_JSON (Item : Observed_Comparison) return String;

   procedure Run
     (Self   : in out Adapter'Class;
      Trace  : Flyology_TLA.Traces.Trace;
      Limits : Flyology_TLA.Traces.Load_Limits;
      Result : out Replay_Result);

   procedure Run
     (Self   : in out Adapter'Class;
      Trace  : Flyology_TLA.Traces.Trace;
      Limits : Flyology_TLA.Traces.Load_Limits;
      Result : out Replay_Result_V2);

   procedure Write_Result
     (Item         : Replay_Result;
      Trace_SHA256 : String;
      Path         : String);

   procedure Write_Result
     (Item         : Replay_Result_V2;
      Trace_SHA256 : String;
      Path         : String);

private

   type Observed_Comparison
     (Kind : Observation_Kind := No_Observation) is record
      case Kind is
         when No_Observation =>
            null;
         when Initial_State_Observation =>
            Initial_State_JSON : Ada.Strings.Unbounded.Unbounded_String;
         when Step_Observation =>
            Step_Outcome_JSON : Ada.Strings.Unbounded.Unbounded_String;
            Step_State_JSON   : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

end Flyology_TLA.Replay;
