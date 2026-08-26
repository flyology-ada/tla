with Ada.Exceptions;
with Ada.Strings;
with Ada.Strings.Fixed;
with Flyology_TLA.JSON;
with Flyology_TLA.Result_Encoding;

package body Flyology_TLA.Reporting is

   use Ada.Strings.Unbounded;
   use type Flyology_TLA.JSON.Value_Kind;
   use type Flyology_TLA.Replay.Observation_Kind;
   use type Flyology_TLA.Replay.Verdict;

   function Is_Lower_Hex_SHA256 (Value : String) return Boolean is
     (Value'Length = 64
      and then (for all Item of Value => Item in '0' .. '9' | 'a' .. 'f'));

   procedure Check_String
     (Value : String; Limit : Positive; Label : String)
   is
   begin
      if Value'Length = 0 then
         raise Result_Error with Label & " is empty";
      elsif Value'Length > Limit then
         raise Result_Error with Label & " exceeds caller limit";
      end if;
   end Check_String;

   function Decode_Verdict (Value : String) return Flyology_TLA.Replay.Verdict is
   begin
      if Value = "conformant" then
         return Flyology_TLA.Replay.Conformant;
      elsif Value = "diverged" then
         return Flyology_TLA.Replay.Diverged;
      elsif Value = "adapter-error" then
         return Flyology_TLA.Replay.Adapter_Error;
      elsif Value = "invalid-trace" then
         return Flyology_TLA.Replay.Invalid_Trace;
      else
         raise Result_Error with "unsupported result verdict";
      end if;
   end Decode_Verdict;

   function Parse_Document
     (Source       : String;
      Limits       : Flyology_TLA.Traces.Load_Limits;
      Expected_Format : String;
      Trace_SHA256 : out Unbounded_String)
      return Flyology_TLA.Replay.Replay_Result_V2
   is
      Root     : Flyology_TLA.JSON.Value;
      Summary  : Flyology_TLA.Replay.Replay_Result;
      Detailed : Flyology_TLA.Replay.Replay_Result_V2;
   begin
      if Source'Length > Limits.Maximum_File_Bytes then
         raise Result_Error with "result source exceeds caller byte limit";
      end if;
      Flyology_TLA.JSON.Validate
        (Source,
         Limits.Maximum_JSON_Depth,
         Limits.Maximum_Name_Bytes,
         Limits.Maximum_Object_Names);
      Root := Flyology_TLA.JSON.Root (Source);
      declare
         Format : constant String :=
           Flyology_TLA.JSON.String_Data
             (Source, Flyology_TLA.JSON.Member (Source, Root, "format"));
         Verdict_Text : constant String :=
           Flyology_TLA.JSON.String_Data
             (Source, Flyology_TLA.JSON.Member (Source, Root, "verdict"));
         Trace_Identity : constant String :=
           Flyology_TLA.JSON.String_Data
             (Source, Flyology_TLA.JSON.Member (Source, Root, "trace_sha256"));
         Compared_Steps : constant Natural :=
           Flyology_TLA.JSON.Natural_Data
             (Source, Flyology_TLA.JSON.Member (Source, Root, "compared_steps"));
         Failure_Node : constant Flyology_TLA.JSON.Value :=
           Flyology_TLA.JSON.Member (Source, Root, "failure");
         Status : constant Flyology_TLA.Replay.Verdict :=
           Decode_Verdict (Verdict_Text);
      begin
         if Flyology_TLA.JSON.Kind (Root) /= Flyology_TLA.JSON.Object_Value
           or else Flyology_TLA.JSON.Object_Length (Source, Root) /= 5
         then
            raise Result_Error with "result envelope has unknown or missing members";
         elsif Format /= Expected_Format then
            raise Result_Error with "unsupported result format";
         elsif not Is_Lower_Hex_SHA256 (Trace_Identity) then
            raise Result_Error with "result trace_sha256 is not canonical";
         elsif Compared_Steps > Limits.Maximum_Steps then
            raise Result_Error with "result compared step count exceeds caller limit";
         end if;
         Check_String (Verdict_Text, Limits.Maximum_String_Bytes, "result verdict");
         Summary.Status := Status;
         Summary.Compared_Steps := Compared_Steps;
         if Status = Flyology_TLA.Replay.Conformant then
            if Flyology_TLA.JSON.Kind (Failure_Node) /= Flyology_TLA.JSON.Null_Value then
               raise Result_Error with "conformant result has a failure object";
            end if;
         else
            if Flyology_TLA.JSON.Kind (Failure_Node) /= Flyology_TLA.JSON.Object_Value
              or else Flyology_TLA.JSON.Object_Length (Source, Failure_Node) /=
                (if Expected_Format = "flyology.tla.result/2"
                   and then Status = Flyology_TLA.Replay.Diverged
                 then 5
                 else 4)
            then
               raise Result_Error with "nonconformant result has an invalid failure object";
            end if;
            declare
               Step : constant Natural :=
                 Flyology_TLA.JSON.Natural_Data
                   (Source, Flyology_TLA.JSON.Member (Source, Failure_Node, "step"));
               Property : constant String :=
                 Flyology_TLA.JSON.String_Data
                   (Source, Flyology_TLA.JSON.Member (Source, Failure_Node, "property"));
               Fingerprint : constant String :=
                 Flyology_TLA.JSON.String_Data
                   (Source, Flyology_TLA.JSON.Member (Source, Failure_Node, "fingerprint"));
               Detail : constant String :=
                 Flyology_TLA.JSON.String_Data
                   (Source, Flyology_TLA.JSON.Member (Source, Failure_Node, "detail"));
            begin
               if Step > Limits.Maximum_Steps then
                  raise Result_Error with "result failure step exceeds caller limit";
               end if;
               Check_String (Property, Limits.Maximum_String_Bytes, "result property");
               Check_String (Fingerprint, Limits.Maximum_String_Bytes, "result fingerprint");
               Check_String (Detail, Limits.Maximum_Value_Bytes, "result detail");
               Summary.Failure_Step := Step;
               Summary.Property_Name := To_Unbounded_String (Property);
               Summary.Fingerprint := To_Unbounded_String (Fingerprint);
               Summary.Detail := To_Unbounded_String (Detail);

               if Expected_Format = "flyology.tla.result/2"
                 and then Status = Flyology_TLA.Replay.Diverged
               then
                  declare
                     Observed_Node : constant Flyology_TLA.JSON.Value :=
                       Flyology_TLA.JSON.Member (Source, Failure_Node, "observed");
                  begin
                     if Flyology_TLA.JSON.Kind (Observed_Node) /=
                       Flyology_TLA.JSON.Object_Value
                       or else Flyology_TLA.JSON.Object_Length
                         (Source, Observed_Node) /= 2
                     then
                        raise Result_Error with
                          "diverged result/2 has an invalid observed object";
                     end if;
                     declare
                        Outcome_Node : constant Flyology_TLA.JSON.Value :=
                          Flyology_TLA.JSON.Member (Source, Observed_Node, "outcome");
                        State_Node : constant Flyology_TLA.JSON.Value :=
                          Flyology_TLA.JSON.Member (Source, Observed_Node, "state");
                        State : constant String := Flyology_TLA.JSON.Canonical_Value
                          (Flyology_TLA.JSON.Image (Source, State_Node),
                           Limits.Maximum_JSON_Depth,
                           Limits.Maximum_Name_Bytes,
                           Limits.Maximum_Object_Names,
                           Limits.Maximum_String_Bytes,
                           Limits.Maximum_Value_Bytes);
                     begin
                        if Step = 0 then
                           if Flyology_TLA.JSON.Kind (Outcome_Node) /=
                             Flyology_TLA.JSON.Null_Value
                           then
                              raise Result_Error with
                                "initial divergence observed outcome is not null";
                           end if;
                             Detailed :=
                               Flyology_TLA.Replay.With_Initial_Observation
                               (Summary, State, Limits);
                        else
                           declare
                              Outcome : constant String :=
                                Flyology_TLA.JSON.Canonical_Value
                                  (Flyology_TLA.JSON.Image (Source, Outcome_Node),
                                   Limits.Maximum_JSON_Depth,
                                   Limits.Maximum_Name_Bytes,
                                   Limits.Maximum_Object_Names,
                                   Limits.Maximum_String_Bytes,
                                   Limits.Maximum_Value_Bytes);
                           begin
                              Detailed :=
                                Flyology_TLA.Replay.With_Step_Observation
                                  (Summary, Outcome, State, Limits);
                           end;
                        end if;
                     end;
                  end;
               end if;
            end;
         end if;

         if Expected_Format = "flyology.tla.result/2" then
            case Status is
               when Flyology_TLA.Replay.Conformant =>
                  Detailed := Flyology_TLA.Replay.To_Version_2 (Summary);
               when Flyology_TLA.Replay.Diverged =>
                  if Summary.Compared_Steps /= Summary.Failure_Step then
                     raise Result_Error with
                       "diverged result/2 failure is not a completed comparison";
                  end if;
               when Flyology_TLA.Replay.Adapter_Error =>
                  if Summary.Failure_Step = 0 then
                     if Summary.Compared_Steps /= 0 then
                        raise Result_Error with
                          "reset adapter-error result/2 has compared steps";
                     end if;
                  elsif Summary.Failure_Step - 1 /= Summary.Compared_Steps then
                     raise Result_Error with
                       "adapter-error result/2 failure does not follow compared steps";
                  end if;
                  Detailed := Flyology_TLA.Replay.To_Version_2 (Summary);
               when Flyology_TLA.Replay.Invalid_Trace =>
                  if Summary.Failure_Step /= 0
                    or else Summary.Compared_Steps /= 0
                  then
                     raise Result_Error with
                       "invalid-trace result/2 has replay comparison state";
                  end if;
                  Detailed := Flyology_TLA.Replay.To_Version_2 (Summary);
            end case;
         else
            Detailed := Flyology_TLA.Replay.To_Version_2 (Summary);
         end if;
         Trace_SHA256 := To_Unbounded_String (Trace_Identity);
      end;
      return Detailed;
   exception
      when Error : Flyology_TLA.JSON.JSON_Error =>
         raise Result_Error with Ada.Exceptions.Exception_Message (Error);
   end Parse_Document;

   function Parse_JSON
     (Source       : String;
      Limits       : Flyology_TLA.Traces.Load_Limits;
      Trace_SHA256 : out Unbounded_String)
      return Flyology_TLA.Replay.Replay_Result
   is
      Detailed : constant Flyology_TLA.Replay.Replay_Result_V2 :=
        Parse_Document
          (Source, Limits, "flyology.tla.result/1", Trace_SHA256);
   begin
      return Detailed.Summary;
   end Parse_JSON;

   function Parse_JSON_V2
     (Source       : String;
      Limits       : Flyology_TLA.Traces.Load_Limits;
      Trace_SHA256 : out Unbounded_String)
      return Flyology_TLA.Replay.Replay_Result_V2
   is
     (Parse_Document
        (Source, Limits, "flyology.tla.result/2", Trace_SHA256));

   function Escape (Value : String) return String is
      Hex    : constant String := "0123456789abcdef";
      Result : Unbounded_String;
   begin
      for Item of Value loop
         case Item is
            when '\' =>
               Append (Result, "\\");
            when ASCII.LF =>
               Append (Result, "\n");
            when ASCII.CR =>
               Append (Result, "\r");
            when ASCII.HT =>
               Append (Result, "\t");
            when Character'Val (0) .. Character'Val (8) |
                 Character'Val (11) .. Character'Val (12) |
                 Character'Val (14) .. Character'Val (31) |
                 Character'Val (127) =>
               Append
                 (Result,
                  "\x"
                  & Hex (Character'Pos (Item) / 16 + 1)
                  & Hex (Character'Pos (Item) mod 16 + 1));
            when others =>
               Append (Result, Item);
         end case;
      end loop;
      return To_String (Result);
   end Escape;

   function Natural_Image (Value : Natural) return String is
     (Ada.Strings.Fixed.Trim (Natural'Image (Value), Ada.Strings.Both));

   function Verdict_Image
     (Value : Flyology_TLA.Replay.Verdict) return String
   is
     (case Value is
        when Flyology_TLA.Replay.Conformant    => "conformant",
        when Flyology_TLA.Replay.Diverged      => "diverged",
        when Flyology_TLA.Replay.Adapter_Error => "adapter-error",
        when Flyology_TLA.Replay.Invalid_Trace => "invalid-trace");

   function Value_Or (Value : Unbounded_String; Fallback : String) return String is
     (if Length (Value) = 0 then Fallback else Escape (To_String (Value)));

   function Image
     (Result : Flyology_TLA.Replay.Replay_Result;
      Level  : Verbosity) return String
   is
      Verdict     : constant String := Verdict_Image (Result.Status);
      Property    : constant String := Value_Or (Result.Property_Name, "tla-conformance");
      Fingerprint : constant String := Value_Or (Result.Fingerprint, "unspecified-failure");
      Detail      : constant String :=
        Value_Or (Result.Detail, "adapter reported failure without detail");
   begin
      case Level is
         when Terse =>
            if Result.Status = Flyology_TLA.Replay.Conformant then
               return
                 "conformant:"
                 & Natural'Image (Result.Compared_Steps)
                 & " modeled steps";
            else
               return
                 Verdict
                 & " at step"
                 & Natural'Image (Result.Failure_Step)
                 & ": "
                 & Fingerprint;
            end if;

         when Verbose =>
            return
              "Verdict: " & Verdict & ASCII.LF
              & "Compared steps: " & Natural_Image (Result.Compared_Steps) & ASCII.LF
              & "Failure step: "
              & (if Result.Status = Flyology_TLA.Replay.Conformant
                 then "none"
                 else Natural_Image (Result.Failure_Step))
              & ASCII.LF
              & "Property: "
              & (if Result.Status = Flyology_TLA.Replay.Conformant then "none" else Property)
              & ASCII.LF
              & "Fingerprint: "
              & (if Result.Status = Flyology_TLA.Replay.Conformant then "none" else Fingerprint)
              & ASCII.LF
              & "Detail: "
              & (if Result.Status = Flyology_TLA.Replay.Conformant then "none" else Detail);
      end case;
   end Image;

   function Image
     (Result : Flyology_TLA.Replay.Replay_Result_V2;
      Level  : Verbosity) return String
   is
      Base : constant String := Image (Result.Summary, Level);
   begin
      if Level = Terse then
         return Base;
      elsif Result.Observed.Kind = Flyology_TLA.Replay.No_Observation then
         return
           Base & ASCII.LF
           & "Observed outcome: none" & ASCII.LF
           & "Observed state: none";
      else
         return
           Base & ASCII.LF
           & "Observed outcome: "
           & (if Result.Observed.Kind =
               Flyology_TLA.Replay.Initial_State_Observation
              then "none"
              else Escape (Flyology_TLA.Replay.Outcome_JSON (Result.Observed)))
           & ASCII.LF
           & "Observed state: "
           & Escape (Flyology_TLA.Replay.State_JSON (Result.Observed));
      end if;
   end Image;

   function JSON_Image
     (Result       : Flyology_TLA.Replay.Replay_Result;
      Trace_SHA256 : String) return String
   is
     (Flyology_TLA.Result_Encoding.JSON_Image (Result, Trace_SHA256));

   function JSON_Image
     (Result       : Flyology_TLA.Replay.Replay_Result_V2;
      Trace_SHA256 : String) return String
   is
     (Flyology_TLA.Result_Encoding.JSON_Image (Result, Trace_SHA256));

   procedure Put
     (Result : Flyology_TLA.Replay.Replay_Result;
      Level  : Verbosity)
   is
   begin
      Put (Ada.Text_IO.Standard_Output, Result, Level);
   end Put;

   procedure Put
     (Result : Flyology_TLA.Replay.Replay_Result_V2;
      Level  : Verbosity)
   is
   begin
      Put (Ada.Text_IO.Standard_Output, Result, Level);
   end Put;

   procedure Put
     (File   : Ada.Text_IO.File_Type;
      Result : Flyology_TLA.Replay.Replay_Result;
      Level  : Verbosity)
   is
   begin
      Ada.Text_IO.Put_Line (File, Image (Result, Level));
   end Put;

   procedure Put
     (File   : Ada.Text_IO.File_Type;
      Result : Flyology_TLA.Replay.Replay_Result_V2;
      Level  : Verbosity)
   is
   begin
      Ada.Text_IO.Put_Line (File, Image (Result, Level));
   end Put;

   procedure Put_JSON
     (Result       : Flyology_TLA.Replay.Replay_Result;
      Trace_SHA256 : String)
   is
   begin
      Put_JSON (Ada.Text_IO.Standard_Output, Result, Trace_SHA256);
   end Put_JSON;

   procedure Put_JSON
     (Result       : Flyology_TLA.Replay.Replay_Result_V2;
      Trace_SHA256 : String)
   is
   begin
      Put_JSON (Ada.Text_IO.Standard_Output, Result, Trace_SHA256);
   end Put_JSON;

   procedure Put_JSON
     (File         : Ada.Text_IO.File_Type;
      Result       : Flyology_TLA.Replay.Replay_Result;
      Trace_SHA256 : String)
   is
   begin
      Ada.Text_IO.Put_Line (File, JSON_Image (Result, Trace_SHA256));
   end Put_JSON;

   procedure Put_JSON
     (File         : Ada.Text_IO.File_Type;
      Result       : Flyology_TLA.Replay.Replay_Result_V2;
      Trace_SHA256 : String)
   is
   begin
      Ada.Text_IO.Put_Line (File, JSON_Image (Result, Trace_SHA256));
   end Put_JSON;

   procedure Write_JSON
     (Result       : Flyology_TLA.Replay.Replay_Result;
      Trace_SHA256 : String;
      Path         : String)
   is
      Output : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Create (Output, Ada.Text_IO.Out_File, Path);
      Put_JSON (Output, Result, Trace_SHA256);
      Ada.Text_IO.Close (Output);
   exception
      when others =>
         if Ada.Text_IO.Is_Open (Output) then
            Ada.Text_IO.Close (Output);
         end if;
         raise;
   end Write_JSON;

   procedure Write_JSON
     (Result       : Flyology_TLA.Replay.Replay_Result_V2;
      Trace_SHA256 : String;
      Path         : String)
   is
      Output : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Create (Output, Ada.Text_IO.Out_File, Path);
      Put_JSON (Output, Result, Trace_SHA256);
      Ada.Text_IO.Close (Output);
   exception
      when others =>
         if Ada.Text_IO.Is_Open (Output) then
            Ada.Text_IO.Close (Output);
         end if;
         raise;
   end Write_JSON;

end Flyology_TLA.Reporting;
