with Ada.Exceptions;
with Flyology_TLA.JSON;
with Flyology_TLA.Reporting;

package body Flyology_TLA.Replay is

   use Ada.Strings.Unbounded;

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
      Adapter_Result : Adapter_Outcome;
      Observed_State : Unbounded_String;
      Compared       : Comparison;
      Current_Step   : Natural := 0;
   begin
      Result :=
        (Status         => Adapter_Error,
         Compared_Steps => 0,
         Failure_Step   => 0,
         Property_Name  => To_Unbounded_String ("tla-conformance"),
         Fingerprint    => Null_Unbounded_String,
         Detail         => Null_Unbounded_String);
      Self.Reset (Observed_State, Adapter_Result);
      if not Adapter_Result.Succeeded then
         Result.Fingerprint := To_Unbounded_String ("adapter-reset");
         Result.Detail := Adapter_Result.Detail;
         return;
      end if;
      if Length (Observed_State) > Limits.Maximum_Value_Bytes then
         Result.Fingerprint := To_Unbounded_String ("adapter-observation-limit:reset");
         Result.Detail := To_Unbounded_String ("adapter initial state exceeds caller value limit");
         return;
      end if;
      begin
         Self.Compare_Initial_State
           (To_String (Trace.Initial_State_JSON), To_String (Observed_State), Limits, Compared);
      exception
         when Error : Flyology_TLA.JSON.JSON_Error =>
            Result.Fingerprint := To_Unbounded_String ("adapter-observation-json:reset");
            Result.Detail := To_Unbounded_String (Ada.Exceptions.Exception_Message (Error));
            return;
      end;
      if not Compared.Equivalent then
         Result.Status := Diverged;
         Result.Fingerprint := Compared.Fingerprint;
         Result.Detail := Compared.Detail;
         return;
      end if;
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
               Result.Failure_Step := Step.Index;
               Result.Fingerprint := To_Unbounded_String ("adapter:" & To_String (Step.Action));
               Result.Detail := Adapter_Result.Detail;
               return;
            end if;
            if Length (Observed_Outcome) > Limits.Maximum_Value_Bytes
              or else Length (Observed_State) > Limits.Maximum_Value_Bytes
            then
               Result.Failure_Step := Step.Index;
               Result.Fingerprint :=
                 To_Unbounded_String ("adapter-observation-limit:" & To_String (Step.Action));
               Result.Detail :=
                 To_Unbounded_String ("adapter outcome or state exceeds caller value limit");
               return;
            end if;
            begin
               Self.Compare_Step
                 (Command,
                  To_String (Step.Expected_Outcome_JSON),
                  To_String (Step.Expected_State_JSON),
                  To_String (Observed_Outcome),
                  To_String (Observed_State),
                  Limits,
                  Compared);
            exception
               when Error : Flyology_TLA.JSON.JSON_Error =>
                  Result.Failure_Step := Step.Index;
                  Result.Fingerprint :=
                    To_Unbounded_String ("adapter-observation-json:" & To_String (Step.Action));
                  Result.Detail := To_Unbounded_String (Ada.Exceptions.Exception_Message (Error));
                  return;
            end;
            Result.Compared_Steps := Step.Index;
            if not Compared.Equivalent then
               Result.Status := Diverged;
               Result.Failure_Step := Step.Index;
               Result.Fingerprint := Compared.Fingerprint;
               Result.Detail := Compared.Detail;
               return;
            end if;
         end;
      end loop;
      Result.Status := Conformant;
   exception
      when Error : others =>
         Result.Status := Adapter_Error;
         Result.Failure_Step := Current_Step;
         Result.Fingerprint := To_Unbounded_String ("adapter-exception");
         Result.Detail := To_Unbounded_String (Ada.Exceptions.Exception_Information (Error));
   end Run;

   procedure Write_Result
     (Item         : Replay_Result;
      Trace_SHA256 : String;
      Path         : String)
   is
   begin
      Flyology_TLA.Reporting.Write_JSON (Item, Trace_SHA256, Path);
   end Write_Result;

end Flyology_TLA.Replay;
