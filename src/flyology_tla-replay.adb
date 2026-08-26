with Ada.Exceptions;
with Flyology_TLA.JSON;
with Flyology_TLA.Reporting;

package body Flyology_TLA.Replay is

   use Ada.Strings.Unbounded;

   function Canonical_Observation
     (Source : String;
      Limits : Flyology_TLA.Traces.Load_Limits) return String
   is
     (Flyology_TLA.JSON.Canonical_Value
        (Source,
         Limits.Maximum_JSON_Depth,
         Limits.Maximum_Name_Bytes,
         Limits.Maximum_Object_Names,
         Limits.Maximum_String_Bytes,
         Limits.Maximum_Value_Bytes));

   function To_Version_2 (Summary : Replay_Result) return Replay_Result_V2 is
     ((Summary => Summary, Observed => (Kind => No_Observation)));

   function With_Initial_Observation
     (Summary             : Replay_Result;
      Observed_State_JSON : String;
      Limits              : Flyology_TLA.Traces.Load_Limits) return Replay_Result_V2
   is
     (Summary  => Summary,
      Observed =>
        (Kind               => Initial_State_Observation,
         Initial_State_JSON =>
           To_Unbounded_String
             (Canonical_Observation (Observed_State_JSON, Limits))));

   function With_Step_Observation
     (Summary               : Replay_Result;
      Observed_Outcome_JSON : String;
      Observed_State_JSON   : String;
      Limits                : Flyology_TLA.Traces.Load_Limits) return Replay_Result_V2
   is
     (Summary  => Summary,
      Observed =>
        (Kind              => Step_Observation,
         Step_Outcome_JSON =>
           To_Unbounded_String
             (Canonical_Observation (Observed_Outcome_JSON, Limits)),
         Step_State_JSON   =>
           To_Unbounded_String
             (Canonical_Observation (Observed_State_JSON, Limits))));

   function Outcome_JSON (Item : Observed_Comparison) return String is
   begin
      case Item.Kind is
         when Step_Observation =>
            return To_String (Item.Step_Outcome_JSON);
         when No_Observation | Initial_State_Observation =>
            return "";
      end case;
   end Outcome_JSON;

   function State_JSON (Item : Observed_Comparison) return String is
   begin
      case Item.Kind is
         when Initial_State_Observation =>
            return To_String (Item.Initial_State_JSON);
         when Step_Observation =>
            return To_String (Item.Step_State_JSON);
         when No_Observation =>
            return "";
      end case;
   end State_JSON;

   procedure Compare_Initial_State
     (Self          : in out Adapter;
      Expected_JSON : String;
      Observed_JSON : String;
      Limits        : Flyology_TLA.Traces.Load_Limits;
      Result        : out Comparison)
   is
      pragma Unreferenced (Self);
   begin
      Result.Equivalent :=
        Observed_JSON'Length <= Limits.Maximum_Value_Bytes
        and then Flyology_TLA.JSON.Equivalent
          (Expected_JSON,
           Observed_JSON,
           Limits.Maximum_JSON_Depth,
           Limits.Maximum_Name_Bytes,
           Limits.Maximum_Object_Names);
      if not Result.Equivalent then
         Result.Fingerprint := To_Unbounded_String ("initial-state");
         Result.Detail := To_Unbounded_String ("initial semantic state differs from the model");
      end if;
   end Compare_Initial_State;

   procedure Compare_Step
     (Self                  : in out Adapter;
      Command               : Replay_Command;
      Expected_Outcome_JSON : String;
      Expected_State_JSON   : String;
      Observed_Outcome_JSON : String;
      Observed_State_JSON   : String;
      Limits                : Flyology_TLA.Traces.Load_Limits;
      Result                : out Comparison)
   is
      pragma Unreferenced (Self);
      Action : constant String := To_String (Command.Action);
      Outcome_Matches : constant Boolean :=
        Observed_Outcome_JSON'Length <= Limits.Maximum_Value_Bytes
        and then Flyology_TLA.JSON.Equivalent
          (Expected_Outcome_JSON,
           Observed_Outcome_JSON,
           Limits.Maximum_JSON_Depth,
           Limits.Maximum_Name_Bytes,
           Limits.Maximum_Object_Names);
      State_Matches   : constant Boolean :=
        Observed_State_JSON'Length <= Limits.Maximum_Value_Bytes
        and then Flyology_TLA.JSON.Equivalent
          (Expected_State_JSON,
           Observed_State_JSON,
           Limits.Maximum_JSON_Depth,
           Limits.Maximum_Name_Bytes,
           Limits.Maximum_Object_Names);
   begin
      Result.Equivalent := Outcome_Matches and State_Matches;
      if not Result.Equivalent then
         Result.Fingerprint := To_Unbounded_String
           ((if not Outcome_Matches then "outcome:" else "state:") & Action);
         Result.Detail := To_Unbounded_String
           ((if not Outcome_Matches
             then "observed outcome differs from the model after "
             else "observed semantic state differs from the model after ")
            & Action);
      end if;
   end Compare_Step;

   procedure Run
     (Self   : in out Adapter'Class;
      Trace  : Flyology_TLA.Traces.Trace;
      Limits : Flyology_TLA.Traces.Load_Limits;
      Result : out Replay_Result)
   is
      Detailed : Replay_Result_V2;
   begin
      Run (Self, Trace, Limits, Detailed);
      Result := Detailed.Summary;
   end Run;

   procedure Run
     (Self   : in out Adapter'Class;
      Trace  : Flyology_TLA.Traces.Trace;
      Limits : Flyology_TLA.Traces.Load_Limits;
      Result : out Replay_Result_V2)
   is
      Adapter_Result : Adapter_Outcome;
      Observed_State : Unbounded_String;
      Compared       : Comparison;
      Current_Step   : Natural := 0;
   begin
      Result :=
        (Summary =>
           (Status         => Adapter_Error,
            Compared_Steps => 0,
            Failure_Step   => 0,
            Property_Name  => To_Unbounded_String ("tla-conformance"),
            Fingerprint    => Null_Unbounded_String,
            Detail         => Null_Unbounded_String),
         Observed => (Kind => No_Observation));
      Self.Reset (Observed_State, Adapter_Result);
      if not Adapter_Result.Succeeded then
         Result.Summary.Fingerprint := To_Unbounded_String ("adapter-reset");
         Result.Summary.Detail := Adapter_Result.Detail;
         return;
      end if;
      if Length (Observed_State) > Limits.Maximum_Value_Bytes then
         Result.Summary.Fingerprint :=
           To_Unbounded_String ("adapter-observation-limit:reset");
         Result.Summary.Detail :=
           To_Unbounded_String ("adapter initial state exceeds caller value limit");
         return;
      end if;
      declare
         Canonical_State : Unbounded_String;
      begin
         Canonical_State := To_Unbounded_String
           (Canonical_Observation (To_String (Observed_State), Limits));
         Self.Compare_Initial_State
           (To_String (Trace.Initial_State_JSON),
            To_String (Observed_State),
            Limits,
            Compared);
         if not Compared.Equivalent then
            Result.Summary.Status := Diverged;
            Result.Summary.Fingerprint := Compared.Fingerprint;
            Result.Summary.Detail := Compared.Detail;
            Result.Observed :=
              (Kind               => Initial_State_Observation,
               Initial_State_JSON => Canonical_State);
            return;
         end if;
      exception
         when Error : Flyology_TLA.JSON.JSON_Error =>
            Result.Summary.Fingerprint :=
              To_Unbounded_String ("adapter-observation-json:reset");
            Result.Summary.Detail :=
              To_Unbounded_String (Ada.Exceptions.Exception_Message (Error));
            return;
      end;
      for Step of Trace.Steps loop
         Current_Step := Step.Index;
         declare
            Observed_Outcome : Unbounded_String;
            Command : constant Replay_Command :=
              (Index        => Step.Index,
               Action       => Step.Action,
               Role         => Step.Role,
               Input_JSON   => Step.Input_JSON,
               Model_Source => Step.Model_Source);
         begin
            Self.Apply
              (Command,
               Observed_Outcome,
               Observed_State,
               Adapter_Result);
            if not Adapter_Result.Succeeded then
               Result.Summary.Failure_Step := Step.Index;
               Result.Summary.Fingerprint :=
                 To_Unbounded_String ("adapter:" & To_String (Step.Action));
               Result.Summary.Detail := Adapter_Result.Detail;
               return;
            end if;
            if Length (Observed_Outcome) > Limits.Maximum_Value_Bytes
              or else Length (Observed_State) > Limits.Maximum_Value_Bytes
            then
               Result.Summary.Failure_Step := Step.Index;
               Result.Summary.Fingerprint :=
                 To_Unbounded_String ("adapter-observation-limit:" & To_String (Step.Action));
               Result.Summary.Detail :=
                 To_Unbounded_String ("adapter outcome or state exceeds caller value limit");
               return;
            end if;
            declare
               Canonical_Outcome : Unbounded_String;
               Canonical_State   : Unbounded_String;
            begin
               Canonical_Outcome := To_Unbounded_String
                 (Canonical_Observation (To_String (Observed_Outcome), Limits));
               Canonical_State := To_Unbounded_String
                 (Canonical_Observation (To_String (Observed_State), Limits));
               Self.Compare_Step
                 (Command,
                  To_String (Step.Expected_Outcome_JSON),
                  To_String (Step.Expected_State_JSON),
                  To_String (Observed_Outcome),
                  To_String (Observed_State),
                  Limits,
                  Compared);
               Result.Summary.Compared_Steps := Step.Index;
               if not Compared.Equivalent then
                  Result.Summary.Status := Diverged;
                  Result.Summary.Failure_Step := Step.Index;
                  Result.Summary.Fingerprint := Compared.Fingerprint;
                  Result.Summary.Detail := Compared.Detail;
                  Result.Observed :=
                    (Kind              => Step_Observation,
                     Step_Outcome_JSON => Canonical_Outcome,
                     Step_State_JSON   => Canonical_State);
                  return;
               end if;
            exception
               when Error : Flyology_TLA.JSON.JSON_Error =>
                  Result.Summary.Failure_Step := Step.Index;
                  Result.Summary.Fingerprint :=
                    To_Unbounded_String ("adapter-observation-json:" & To_String (Step.Action));
                  Result.Summary.Detail :=
                    To_Unbounded_String (Ada.Exceptions.Exception_Message (Error));
                  return;
            end;
         end;
      end loop;
      Result.Summary.Status := Conformant;
   exception
      when Error : others =>
         Result.Summary.Status := Adapter_Error;
         Result.Summary.Failure_Step := Current_Step;
         Result.Summary.Fingerprint := To_Unbounded_String ("adapter-exception");
         Result.Summary.Detail :=
           To_Unbounded_String (Ada.Exceptions.Exception_Information (Error));
         Result.Observed := (Kind => No_Observation);
   end Run;

   procedure Write_Result
     (Item         : Replay_Result;
      Trace_SHA256 : String;
      Path         : String)
   is
   begin
      Flyology_TLA.Reporting.Write_JSON (Item, Trace_SHA256, Path);
   end Write_Result;

   procedure Write_Result
     (Item         : Replay_Result_V2;
      Trace_SHA256 : String;
      Path         : String)
   is
   begin
      Flyology_TLA.Reporting.Write_JSON (Item, Trace_SHA256, Path);
   end Write_Result;

end Flyology_TLA.Replay;
