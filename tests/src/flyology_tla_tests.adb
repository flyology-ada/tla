with Ada.Command_Line;
with Ada.Strings;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology_TLA.Replay;
with Flyology_TLA.Reporting;
with Flyology_TLA.Traces;
with GNAT.SHA256;

procedure Flyology_TLA_Tests is

   use Ada.Strings.Unbounded;
   use type Flyology_TLA.Replay.Observation_Kind;
   use type Flyology_TLA.Replay.Verdict;

   type Counter_Adapter is new Flyology_TLA.Replay.Adapter with record
      Count        : Natural := 0;
      Diverge      : Boolean := False;
      Outcome_Diverge : Boolean := False;
      Initial_Diverge : Boolean := False;
      Adapter_Fail : Boolean := False;
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
      Observed_State_JSON := To_Unbounded_String
        (if Self.Initial_Diverge then "{ ""count"" : 98 }" else "{ ""count"" : 0 }");
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
          (if Self.Invalid_JSON then "{"
           elsif Self.Outcome_Diverge then "{ ""accepted"" : false }"
           else "{ ""accepted"" : true }");
      Observed_State_JSON :=
        To_Unbounded_String
          (if Self.Diverge
           then "{""count"":99}"
           else
             "{""count"":"
             & Ada.Strings.Fixed.Trim (Natural'Image (Self.Count), Ada.Strings.Both)
             & "}");
      Outcome :=
        (if Self.Adapter_Fail
         then
           (Succeeded => False,
            Detail    => To_Unbounded_String ("adapter failed"))
         else (Succeeded => True, Detail => Null_Unbounded_String));
   end Apply;

   Limits : constant Flyology_TLA.Traces.Load_Limits :=
     (Maximum_File_Bytes   => 100_000,
      Maximum_Steps        => 10,
      Maximum_JSON_Depth   => 20,
      Maximum_Object_Names => 1_000,
      Maximum_Name_Bytes   => 1_000,
      Maximum_String_Bytes => 10_000,
      Maximum_Value_Bytes  => 50_000);

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Require;

   procedure Require_Trace_Error (Source : String; Message : String) is
      Ignored : Flyology_TLA.Traces.Trace;
   begin
      Ignored := Flyology_TLA.Traces.Parse (Source, Limits);
      raise Program_Error with Message;
   exception
      when Flyology_TLA.Traces.Trace_Error =>
         null;
   end Require_Trace_Error;

   procedure Require_Result_Error (Source : String; Message : String) is
      Ignored_SHA256 : Unbounded_String;
      Ignored_Result : Flyology_TLA.Replay.Replay_Result;
   begin
      Ignored_Result :=
        Flyology_TLA.Reporting.Parse_JSON (Source, Limits, Ignored_SHA256);
      raise Program_Error with Message;
   exception
      when Flyology_TLA.Reporting.Result_Error =>
         null;
   end Require_Result_Error;

   procedure Require_Result_V2_Error
     (Source        : String;
      Message       : String;
      Active_Limits : Flyology_TLA.Traces.Load_Limits := Limits)
   is
      Ignored_SHA256 : Unbounded_String;
      Ignored_Result : Flyology_TLA.Replay.Replay_Result_V2;
   begin
      Ignored_Result :=
        Flyology_TLA.Reporting.Parse_JSON_V2
          (Source, Active_Limits, Ignored_SHA256);
      raise Program_Error with Message;
   exception
      when Flyology_TLA.Reporting.Result_Error =>
         null;
   end Require_Result_V2_Error;

   Trace : constant Flyology_TLA.Traces.Trace :=
     Flyology_TLA.Traces.Load (Ada.Command_Line.Argument (1), Limits);
   Adapter : Counter_Adapter;
   Result  : Flyology_TLA.Replay.Replay_Result;
   Detailed_Result : Flyology_TLA.Replay.Replay_Result_V2;
   Trace_Identity : constant String :=
     "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
   UTF8_Snowman : constant String :=
     Character'Val (16#E2#) & Character'Val (16#98#) & Character'Val (16#83#);

begin
   declare
      Source : constant String :=
        Flyology_TLA.Traces.Image (Trace, Natural (Trace.Steps.Length));
      Parsed_SHA256 : Unbounded_String;
      Parsed : constant Flyology_TLA.Traces.Trace :=
        Flyology_TLA.Traces.Parse (Source, Limits, Parsed_SHA256);
      With_Unknown_Member : constant String :=
        Source (Source'First .. Source'Last - 1) & ",""unknown"":true}";
   begin
      Require
        (Length (Trace.Model.Configuration_SHA256) = 64,
         "current trace fixture did not load trace/2 configuration identity");
      Require
        (To_String (Parsed_SHA256) = GNAT.SHA256.Digest (Source),
         "in-memory trace parse computed the wrong SHA-256");
      Require
        (Flyology_TLA.Traces.Image (Parsed, Natural (Parsed.Steps.Length)) = Source,
         "in-memory trace parse/image did not round trip canonically");
      Require_Trace_Error
        (With_Unknown_Member,
         "in-memory trace parse accepted an unknown envelope member");
      Require_Trace_Error
        ("{""format"":""flyology.tla.trace/1"",""format"":""flyology.tla.trace/1""}",
         "in-memory trace parse accepted a duplicate envelope member");
   end;

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
   declare
      Trace_Identity : constant String :=
        "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
      Source : constant String :=
        Flyology_TLA.Reporting.JSON_Image (Result, Trace_Identity);
      Parsed_Trace_Identity : Unbounded_String;
      Parsed : constant Flyology_TLA.Replay.Replay_Result :=
        Flyology_TLA.Reporting.Parse_JSON
          (Source, Limits, Parsed_Trace_Identity);
      With_Unknown_Member : constant String :=
        Source (Source'First .. Source'Last - 1) & ",""unknown"":true}";
   begin
      Require
        (Parsed.Status = Flyology_TLA.Replay.Conformant
         and then Parsed.Compared_Steps = 2
         and then To_String (Parsed_Trace_Identity) = Trace_Identity,
         "strict result decoder changed a conformant result");
      Require_Result_Error
        (With_Unknown_Member,
         "strict result decoder accepted an unknown envelope member");
      Require_Result_Error
        ("{""format"":""flyology.tla.result/1"",""format"":""flyology.tla.result/1""}",
         "strict result decoder accepted a duplicate envelope member");
   end;

   Flyology_TLA.Replay.Run (Adapter, Trace, Limits, Detailed_Result);
   Flyology_TLA.Replay.Write_Result
     (Detailed_Result, Trace_Identity, Ada.Command_Line.Argument (4));
   declare
      Source : constant String :=
        Flyology_TLA.Reporting.JSON_Image (Detailed_Result, Trace_Identity);
      Parsed_Trace_Identity : Unbounded_String;
      Parsed : constant Flyology_TLA.Replay.Replay_Result_V2 :=
        Flyology_TLA.Reporting.Parse_JSON_V2
          (Source, Limits, Parsed_Trace_Identity);
   begin
      Require
        (Source =
           "{""format"":""flyology.tla.result/2"","
           & """verdict"":""conformant"","
           & """trace_sha256"":""" & Trace_Identity
           & """,""compared_steps"":2,""failure"":null}",
         "result/2 conformant encoding changed");
      Require
        (Parsed.Summary.Status = Flyology_TLA.Replay.Conformant
         and then Parsed.Observed.Kind = Flyology_TLA.Replay.No_Observation
         and then To_String (Parsed_Trace_Identity) = Trace_Identity,
         "result/2 conformant parse lost fields or exact trace binding");
      Require_Result_Error
        (Source, "result/1 decoder silently accepted result/2");
      Require_Result_V2_Error
        (Flyology_TLA.Reporting.JSON_Image (Result, Trace_Identity),
         "result/2 decoder silently accepted result/1");
   end;

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

   Flyology_TLA.Replay.Run (Adapter, Trace, Limits, Detailed_Result);
   Flyology_TLA.Replay.Write_Result
     (Detailed_Result, Trace_Identity, Ada.Command_Line.Argument (5));
   declare
      Source : constant String :=
        Flyology_TLA.Reporting.JSON_Image (Detailed_Result, Trace_Identity);
      Parsed_Trace_Identity : Unbounded_String;
      Parsed : constant Flyology_TLA.Replay.Replay_Result_V2 :=
        Flyology_TLA.Reporting.Parse_JSON_V2
          (Source, Limits, Parsed_Trace_Identity);
      Unknown_Observed : constant String :=
        Source (Source'First .. Source'Last - 3) & ",""unknown"":true}}}";
      Duplicate_Observed : constant String :=
        Source (Source'First .. Source'Last - 3)
        & ",""state"":{""count"":99}}}}";
   begin
      Require
        (Detailed_Result.Observed.Kind = Flyology_TLA.Replay.Step_Observation
         and then Flyology_TLA.Replay.Outcome_JSON (Detailed_Result.Observed) =
           "{""accepted"":true}"
         and then Flyology_TLA.Replay.State_JSON (Detailed_Result.Observed) =
           "{""count"":99}",
         "step divergence did not retain canonical observed outcome and state");
      Require
        (Parsed.Summary.Fingerprint = Detailed_Result.Summary.Fingerprint
         and then Flyology_TLA.Replay.State_JSON (Parsed.Observed) =
           "{""count"":99}"
         and then To_String (Parsed_Trace_Identity) = Trace_Identity,
         "result/2 state divergence did not round trip");
      Require
        (Flyology_TLA.Reporting.Image
           (Detailed_Result, Flyology_TLA.Reporting.Verbose) =
           Flyology_TLA.Reporting.Image
             (Detailed_Result.Summary, Flyology_TLA.Reporting.Verbose)
           & ASCII.LF & "Observed outcome: {""accepted"":true}"
           & ASCII.LF & "Observed state: {""count"":99}",
         "verbose result/2 report omitted the observed comparison");
      Require_Result_V2_Error
        (Unknown_Observed,
         "result/2 decoder accepted an unknown observed member");
      Require_Result_V2_Error
        (Duplicate_Observed,
         "result/2 decoder accepted a duplicate observed member");
   end;

   Adapter.Diverge := False;
   Adapter.Outcome_Diverge := True;
   Flyology_TLA.Replay.Run (Adapter, Trace, Limits, Detailed_Result);
   Flyology_TLA.Replay.Write_Result
     (Detailed_Result, Trace_Identity, Ada.Command_Line.Argument (6));
   Require
     (Detailed_Result.Summary.Status = Flyology_TLA.Replay.Diverged
      and then To_String (Detailed_Result.Summary.Fingerprint) =
        "outcome:Counter!Increment"
      and then Flyology_TLA.Replay.Outcome_JSON (Detailed_Result.Observed) =
        "{""accepted"":false}"
      and then Flyology_TLA.Replay.State_JSON (Detailed_Result.Observed) =
        "{""count"":1}",
      "outcome divergence did not retain both returned observations");

   Adapter.Outcome_Diverge := False;
   Adapter.Initial_Diverge := True;
   Flyology_TLA.Replay.Run (Adapter, Trace, Limits, Detailed_Result);
   declare
      Source : constant String :=
        Flyology_TLA.Reporting.JSON_Image (Detailed_Result, Trace_Identity);
      Parsed_Trace_Identity : Unbounded_String;
      Parsed : constant Flyology_TLA.Replay.Replay_Result_V2 :=
        Flyology_TLA.Reporting.Parse_JSON_V2
          (Source, Limits, Parsed_Trace_Identity);
   begin
      Require
        (Detailed_Result.Summary.Failure_Step = 0
         and then Detailed_Result.Summary.Compared_Steps = 0
         and then Detailed_Result.Observed.Kind =
           Flyology_TLA.Replay.Initial_State_Observation
         and then Flyology_TLA.Replay.Outcome_JSON
           (Detailed_Result.Observed) = ""
         and then Flyology_TLA.Replay.State_JSON (Detailed_Result.Observed) =
           "{""count"":98}",
         "initial divergence observation has the wrong typed shape");
      Require
        (Parsed.Observed.Kind = Flyology_TLA.Replay.Initial_State_Observation
         and then Source'Length > 0
         and then To_String (Parsed_Trace_Identity) = Trace_Identity,
         "initial divergence result/2 did not round trip");
      Require
        (Ada.Strings.Fixed.Index (Source, """observed"":{""outcome"":null") > 0,
         "initial divergence did not encode the required null outcome sentinel");
   end;

   Adapter.Initial_Diverge := False;

   Adapter.Invalid_JSON := True;
   Flyology_TLA.Replay.Run (Adapter, Trace, Limits, Result);
   Require (Result.Status = Flyology_TLA.Replay.Adapter_Error, "invalid adapter JSON was not rejected");
   Require (Result.Failure_Step = 1, "invalid adapter JSON lost the failure step");
   Require
     (To_String (Result.Fingerprint) = "adapter-observation-json:Counter!Increment",
      "invalid adapter JSON has an unstable fingerprint: "
      & To_String (Result.Fingerprint));

   Flyology_TLA.Replay.Run (Adapter, Trace, Limits, Detailed_Result);
   Require
     (Detailed_Result.Summary.Status = Flyology_TLA.Replay.Adapter_Error
      and then Detailed_Result.Observed.Kind = Flyology_TLA.Replay.No_Observation,
      "invalid observed JSON leaked an observation into adapter-error");

   Adapter.Invalid_JSON := False;
   Adapter.Adapter_Fail := True;
   Flyology_TLA.Replay.Run (Adapter, Trace, Limits, Detailed_Result);
   Flyology_TLA.Replay.Write_Result
     (Detailed_Result, Trace_Identity, Ada.Command_Line.Argument (7));
   declare
      Source : constant String :=
        Flyology_TLA.Reporting.JSON_Image (Detailed_Result, Trace_Identity);
      Injected_Observation : constant String :=
        Source (Source'First .. Source'Last - 2)
        & ",""observed"":{""outcome"":null,""state"":null}}}";
   begin
      Require
        (Detailed_Result.Summary.Status = Flyology_TLA.Replay.Adapter_Error
         and then Detailed_Result.Observed.Kind =
           Flyology_TLA.Replay.No_Observation
         and then Ada.Strings.Fixed.Index (Source, "observed") = 0,
         "adapter failure retained attempted observations");
      Require_Result_V2_Error
        (Injected_Observation,
         "adapter-error result/2 accepted an observed comparison");
   end;
   Adapter.Adapter_Fail := False;

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
   declare
      Trace_Identity : constant String :=
        "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
      Invalid : constant Flyology_TLA.Replay.Replay_Result :=
        (Status         => Flyology_TLA.Replay.Invalid_Trace,
         Compared_Steps => 0,
         Failure_Step   => 0,
         Property_Name  => To_Unbounded_String ("trace-envelope"),
         Fingerprint    => To_Unbounded_String ("invalid-trace"),
         Detail         => To_Unbounded_String ("trace is malformed"));
      Parsed_Trace_Identity : Unbounded_String;
      Parsed : constant Flyology_TLA.Replay.Replay_Result :=
        Flyology_TLA.Reporting.Parse_JSON
          (Flyology_TLA.Reporting.JSON_Image (Invalid, Trace_Identity),
           Limits,
           Parsed_Trace_Identity);
   begin
      Require
        (Parsed.Status = Flyology_TLA.Replay.Invalid_Trace
         and then To_String (Parsed.Fingerprint) = "invalid-trace"
         and then To_String (Parsed_Trace_Identity) = Trace_Identity,
         "strict result decoder cannot represent the schema invalid-trace verdict");

      declare
         Detailed_Invalid : constant Flyology_TLA.Replay.Replay_Result_V2 :=
           Flyology_TLA.Replay.To_Version_2 (Invalid);
         V2_Source : constant String :=
           Flyology_TLA.Reporting.JSON_Image
             (Detailed_Invalid, Trace_Identity);
         Parsed_V2 : constant Flyology_TLA.Replay.Replay_Result_V2 :=
           Flyology_TLA.Reporting.Parse_JSON_V2
             (V2_Source, Limits, Parsed_Trace_Identity);
      begin
         Require
           (Parsed_V2.Summary.Status = Flyology_TLA.Replay.Invalid_Trace
            and then Parsed_V2.Observed.Kind =
              Flyology_TLA.Replay.No_Observation,
            "invalid-trace result/2 gained a comparison");
      end;
   end;

   declare
      V2_Prefix : constant String :=
        "{""format"":""flyology.tla.result/2"","
        & """verdict"":""diverged"","
        & """trace_sha256"":""" & Trace_Identity
        & """,""compared_steps"":1,""failure"":{""step"":1,""property"":"""
        & "tla-conformance"",""fingerprint"":""state:Counter!Increment"","
        & """detail"":""state differs"",""observed"":";
      V2_Suffix : constant String := "}}";
      Noncanonical : constant String :=
        V2_Prefix
        & "{""outcome"": { ""accepted"" : true }, ""state"": { ""count"" : 99 }}"
        & V2_Suffix;
      Null_Outcome : constant String :=
        V2_Prefix & "{""outcome"":null,""state"":null}" & V2_Suffix;
      Conformant_V2 : constant String :=
        "{""format"":""flyology.tla.result/2"","
        & """verdict"":""conformant"","
        & """trace_sha256"":""" & Trace_Identity
        & """,""compared_steps"":2,""failure"":null}";
      Parsed_SHA256 : Unbounded_String;
      Null_Outcome_SHA256 : Unbounded_String;
      Parsed : constant Flyology_TLA.Replay.Replay_Result_V2 :=
        Flyology_TLA.Reporting.Parse_JSON_V2
          (Noncanonical, Limits, Parsed_SHA256);
      Parsed_Null_Outcome : constant Flyology_TLA.Replay.Replay_Result_V2 :=
        Flyology_TLA.Reporting.Parse_JSON_V2
          (Null_Outcome, Limits, Null_Outcome_SHA256);
      Tiny_Value_Limits : constant Flyology_TLA.Traces.Load_Limits :=
        (Limits with delta Maximum_Value_Bytes => 8);
      Tiny_String_Limits : constant Flyology_TLA.Traces.Load_Limits :=
        (Limits with delta Maximum_String_Bytes => 3);
   begin
      Require
        (Flyology_TLA.Replay.Outcome_JSON (Parsed.Observed) =
           "{""accepted"":true}"
         and then Flyology_TLA.Replay.State_JSON (Parsed.Observed) =
           "{""count"":99}"
         and then To_String (Parsed_SHA256) = Trace_Identity,
         "result/2 parser did not canonicalize embedded observations");
      Require
        (Flyology_TLA.Replay.Outcome_JSON
           (Parsed_Null_Outcome.Observed) = "null"
         and then To_String (Null_Outcome_SHA256) = Trace_Identity,
         "result/2 confused an observed null outcome with absence");
      Require_Result_V2_Error
        (Conformant_V2 (Conformant_V2'First .. Conformant_V2'Last - 1)
         & ",""unknown"":true}",
         "result/2 decoder accepted an unknown envelope member");
      Require_Result_V2_Error
        ("{""format"":""flyology.tla.result/2"","
         & """format"":""flyology.tla.result/2""}",
         "result/2 decoder accepted a duplicate envelope member");
      Require_Result_V2_Error
        ("{""format"":""flyology.tla.result/2"","
         & """verdict"":""diverged"","
         & """trace_sha256"":""" & Trace_Identity & ""","
         & """compared_steps"":0,"
         & """failure"":{""step"":1,"
         & """property"":""tla-conformance"","
         & """fingerprint"":""state:Counter!Increment"","
         & """detail"":""state differs"","
         & """observed"":{""outcome"":{},""state"":{}}}}",
         "result/2 decoder accepted a divergence with mismatched step counts");
      Require_Result_V2_Error
        ("{""format"":""flyology.tla.result/2"","
         & """verdict"":""diverged"","
         & """trace_sha256"":""" & Trace_Identity & ""","
         & """compared_steps"":0,"
         & """failure"":{""step"":0,"
         & """property"":""tla-conformance"","
         & """fingerprint"":""initial-state"","
         & """detail"":""state differs"","
         & """observed"":{""outcome"":true,""state"":{}}}}",
         "result/2 decoder accepted a non-null initial outcome");
      Require_Result_V2_Error
        (V2_Prefix & "{""outcome"":{},""state"":{""long"":12345}}" & V2_Suffix,
         "result/2 decoder ignored the independent observed value limit",
         Tiny_Value_Limits);
      Require_Result_V2_Error
        (V2_Prefix & "{""outcome"":""long"",""state"":null}" & V2_Suffix,
         "result/2 decoder ignored nested string limits",
         Tiny_String_Limits);
      Require_Result_V2_Error
        (V2_Prefix & "{""outcome"":{},""state"":{}}" & V2_Suffix
         & " trailing",
         "result/2 decoder accepted malformed trailing data");
      Require_Result_V2_Error
        (V2_Prefix & "{""outcome"":{},""state"":{}}" & V2_Suffix
         & " ",
         "result/2 decoder accepted an oversized result source",
         (Limits with delta Maximum_File_Bytes => 10));
   end;
   Ada.Text_IO.Put_Line ("flyology_tla replay tests passed");
end Flyology_TLA_Tests;
