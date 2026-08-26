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

   type Verdict is (Conformant, Diverged, Adapter_Error);

   type Replay_Result is record
      Status         : Verdict := Adapter_Error;
      Compared_Steps : Natural := 0;
      Failure_Step   : Natural := 0;
      Property_Name  : Ada.Strings.Unbounded.Unbounded_String;
      Fingerprint    : Ada.Strings.Unbounded.Unbounded_String;
      Detail         : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   procedure Run
     (Self   : in out Adapter'Class;
      Trace  : Flyology_TLA.Traces.Trace;
      Limits : Flyology_TLA.Traces.Load_Limits;
      Result : out Replay_Result);

   procedure Write_Result
     (Item         : Replay_Result;
      Trace_SHA256 : String;
      Path         : String);

end Flyology_TLA.Replay;
