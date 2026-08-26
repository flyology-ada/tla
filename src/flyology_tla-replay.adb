with Ada.Exceptions;
with Ada.Strings;
with Ada.Strings.Fixed;
with Ada.Text_IO;
with Flyology_TLA.JSON;

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
      Output : Ada.Text_IO.File_Type;
      Verdict_Text : constant String :=
        (case Item.Status is
           when Conformant    => "conformant",
           when Diverged      => "diverged",
           when Adapter_Error => "adapter-error");
   begin
      if Trace_SHA256'Length /= 64
        or else
          (for some Character_Of_SHA of Trace_SHA256 =>
             Character_Of_SHA not in '0' .. '9' | 'a' .. 'f')
      then
         raise Constraint_Error with "trace SHA-256 is not canonical lowercase hexadecimal";
      end if;
      Ada.Text_IO.Create (Output, Ada.Text_IO.Out_File, Path);
      Ada.Text_IO.Put
        (Output,
         "{""format"":""flyology.tla.result/1"",""verdict"":"
         & Flyology_TLA.JSON.Quote (Verdict_Text)
         & ",""trace_sha256"":"
         & Flyology_TLA.JSON.Quote (Trace_SHA256)
         & ",""compared_steps"":"
         & Ada.Strings.Fixed.Trim (Natural'Image (Item.Compared_Steps), Ada.Strings.Both)
         & ",""failure"":" );
      if Item.Status = Conformant then
         Ada.Text_IO.Put (Output, "null");
      else
         declare
            Property : constant String :=
              (if Length (Item.Property_Name) > 0
               then To_String (Item.Property_Name)
               else "tla-conformance");
            Fingerprint : constant String :=
              (if Length (Item.Fingerprint) > 0
               then To_String (Item.Fingerprint)
               else "unspecified-failure");
            Detail : constant String :=
              (if Length (Item.Detail) > 0
               then To_String (Item.Detail)
               else "adapter reported failure without detail");
         begin
            Ada.Text_IO.Put
              (Output,
               "{""step"":"
               & Ada.Strings.Fixed.Trim (Natural'Image (Item.Failure_Step), Ada.Strings.Both)
               & ",""property"":"
               & Flyology_TLA.JSON.Quote (Property)
               & ",""fingerprint"":"
               & Flyology_TLA.JSON.Quote (Fingerprint)
               & ",""detail"":"
               & Flyology_TLA.JSON.Quote (Detail)
               & "}");
         end;
      end if;
      Ada.Text_IO.Put_Line (Output, "}");
      Ada.Text_IO.Close (Output);
   exception
      when others =>
         if Ada.Text_IO.Is_Open (Output) then
            Ada.Text_IO.Close (Output);
         end if;
         raise;
   end Write_Result;

end Flyology_TLA.Replay;
