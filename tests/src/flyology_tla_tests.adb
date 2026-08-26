with Ada.Command_Line;
with Ada.Strings;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology_TLA.Replay;
with Flyology_TLA.Reporting;
with Flyology_TLA.Traces;

procedure Flyology_TLA_Tests is

   use Ada.Strings.Unbounded;
   use type Flyology_TLA.Replay.Verdict;

   type Counter_Adapter is new Flyology_TLA.Replay.Adapter with record
      Count        : Natural := 0;
      Diverge      : Boolean := False;
      Invalid_JSON : Boolean := False;
   end record;

   overriding procedure Reset
     (Self                : in out Counter_Adapter;
      Observed_State_JSON : out Unbounded_String;
      Outcome             : out Flyology_TLA.Replay.Adapter_Outcome);

   overriding procedure Apply
     (Self                  : in out Counter_Adapter;
      Command               : Flyology_TLA.Replay.Replay_Command;
      Observed_Outcome_JSON : out Unbounded_String;
      Observed_State_JSON   : out Unbounded_String;
      Outcome               : out Flyology_TLA.Replay.Adapter_Outcome);

   procedure Reset
     (Self                : in out Counter_Adapter;
      Observed_State_JSON : out Unbounded_String;
      Outcome             : out Flyology_TLA.Replay.Adapter_Outcome)
   is
   begin
      Self.Count := 0;
      Observed_State_JSON := To_Unbounded_String ("{ ""count"" : 0 }");
      Outcome := (Succeeded => True, Detail => Null_Unbounded_String);
   end Reset;

   procedure Apply
     (Self                  : in out Counter_Adapter;
      Command               : Flyology_TLA.Replay.Replay_Command;
      Observed_Outcome_JSON : out Unbounded_String;
      Observed_State_JSON   : out Unbounded_String;
      Outcome               : out Flyology_TLA.Replay.Adapter_Outcome)
   is
   begin
      if To_String (Command.Action) /= "Counter!Increment"
        or else To_String (Command.Role) /= "increment"
        or else To_String (Command.Input_JSON) /= "{""delta"":1}"
        or else To_String (Command.Model_Source) /= "Counter!Increment"
      then
         Outcome :=
           (Succeeded => False,
            Detail    => To_Unbounded_String ("unexpected action or input"));
         return;
      end if;
      Self.Count := Self.Count + 1;
      Observed_Outcome_JSON :=
        To_Unbounded_String
          (if Self.Invalid_JSON then "{" else "{ ""accepted"" : true }");
      Observed_State_JSON :=
        To_Unbounded_String
          (if Self.Diverge
           then "{""count"":99}"
           else
             "{""count"":"
             & Ada.Strings.Fixed.Trim (Natural'Image (Self.Count), Ada.Strings.Both)
             & "}");
      Outcome := (Succeeded => True, Detail => Null_Unbounded_String);
   end Apply;

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Require;

   Limits : constant Flyology_TLA.Traces.Load_Limits :=
     (Maximum_File_Bytes   => 100_000,
      Maximum_Steps        => 10,
      Maximum_JSON_Depth   => 20,
      Maximum_Object_Names => 1_000,
      Maximum_Name_Bytes   => 1_000,
      Maximum_String_Bytes => 10_000,
      Maximum_Value_Bytes  => 50_000);
   Trace : constant Flyology_TLA.Traces.Trace :=
     Flyology_TLA.Traces.Load (Ada.Command_Line.Argument (1), Limits);
   Adapter : Counter_Adapter;
   Result  : Flyology_TLA.Replay.Replay_Result;
   UTF8_Snowman : constant String :=
     Character'Val (16#E2#) & Character'Val (16#98#) & Character'Val (16#83#);

begin
   Flyology_TLA.Replay.Run (Adapter, Trace, Limits, Result);
   Require (Result.Status = Flyology_TLA.Replay.Conformant, "counter trace did not conform");
   Require (Result.Compared_Steps = 2, "wrong conformance step count");
   Require
     (Flyology_TLA.Reporting.Image (Result, Flyology_TLA.Reporting.Terse) =
        "conformant: 2 modeled steps",
      "terse conformant report changed");
   Require
     (Flyology_TLA.Reporting.Image (Result, Flyology_TLA.Reporting.Verbose) =
        "Verdict: conformant" & ASCII.LF
        & "Compared steps: 2" & ASCII.LF
        & "Failure step: none" & ASCII.LF
        & "Property: none" & ASCII.LF
        & "Fingerprint: none" & ASCII.LF
        & "Detail: none",
      "verbose conformant report changed");
   Flyology_TLA.Replay.Write_Result
     (Result,
      "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
      Ada.Command_Line.Argument (2));

   Adapter.Diverge := True;
   Flyology_TLA.Replay.Run (Adapter, Trace, Limits, Result);
   Require (Result.Status = Flyology_TLA.Replay.Diverged, "divergence was not detected");
   Require (Result.Failure_Step = 1, "wrong first divergent step");
   Require (To_String (Result.Fingerprint) = "state:Counter!Increment", "unstable fingerprint");
   Require
     (Flyology_TLA.Reporting.Image (Result, Flyology_TLA.Reporting.Terse) =
        "diverged at step 1: state:Counter!Increment",
      "terse divergence report changed");
   Require
     (Flyology_TLA.Reporting.Image (Result, Flyology_TLA.Reporting.Verbose) =
        "Verdict: diverged" & ASCII.LF
        & "Compared steps: 1" & ASCII.LF
        & "Failure step: 1" & ASCII.LF
        & "Property: tla-conformance" & ASCII.LF
        & "Fingerprint: state:Counter!Increment" & ASCII.LF
        & "Detail: observed semantic state differs from the model after Counter!Increment",
      "verbose divergence report changed");
   Flyology_TLA.Replay.Write_Result
     (Result,
      "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
      Ada.Command_Line.Argument (3));

   Adapter.Diverge := False;
   Adapter.Invalid_JSON := True;
   Flyology_TLA.Replay.Run (Adapter, Trace, Limits, Result);
   Require (Result.Status = Flyology_TLA.Replay.Adapter_Error, "invalid adapter JSON was not rejected");
   Require (Result.Failure_Step = 1, "invalid adapter JSON lost the failure step");
   Require
     (To_String (Result.Fingerprint) = "adapter-observation-json:Counter!Increment",
      "invalid adapter JSON has an unstable fingerprint");

   Result :=
     (Status         => Flyology_TLA.Replay.Adapter_Error,
      Compared_Steps => 0,
      Failure_Step   => 0,
      Property_Name  => To_Unbounded_String ("tla-conformance"),
      Fingerprint    => To_Unbounded_String ("adapter\fault"),
      Detail         =>
        To_Unbounded_String
          ("line one" & ASCII.LF & "line two " & UTF8_Snowman));
   Require
     (Flyology_TLA.Reporting.Image (Result, Flyology_TLA.Reporting.Terse) =
        "adapter-error at step 0: adapter\\fault",
      "terse report did not escape a backslash");
   Require
     (Flyology_TLA.Reporting.Image (Result, Flyology_TLA.Reporting.Verbose) =
        "Verdict: adapter-error" & ASCII.LF
        & "Compared steps: 0" & ASCII.LF
        & "Failure step: 0" & ASCII.LF
        & "Property: tla-conformance" & ASCII.LF
        & "Fingerprint: adapter\\fault" & ASCII.LF
        & "Detail: line one\nline two " & UTF8_Snowman,
      "verbose report did not escape controls or preserve UTF-8 bytes");
   Ada.Text_IO.Put_Line ("flyology_tla replay tests passed");
end Flyology_TLA_Tests;
