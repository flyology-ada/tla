with Ada.Strings;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Flyology_TLA.JSON;

package body Flyology_TLA.Result_Encoding is

   use Ada.Strings.Unbounded;
   use type Flyology_TLA.Replay.Observation_Kind;
   use type Flyology_TLA.Replay.Verdict;

   function Natural_Image (Value : Natural) return String is
     (Ada.Strings.Fixed.Trim (Natural'Image (Value), Ada.Strings.Both));

   function Verdict_Image (Value : Flyology_TLA.Replay.Verdict) return String is
     (case Value is
        when Flyology_TLA.Replay.Conformant    => "conformant",
        when Flyology_TLA.Replay.Diverged      => "diverged",
        when Flyology_TLA.Replay.Adapter_Error => "adapter-error",
        when Flyology_TLA.Replay.Invalid_Trace => "invalid-trace");

   procedure Check_Trace_SHA256 (Value : String) is
   begin
      if Value'Length /= 64
        or else
          (for some Item of Value => Item not in '0' .. '9' | 'a' .. 'f')
      then
         raise Constraint_Error with
           "trace SHA-256 is not canonical lowercase hexadecimal";
      end if;
   end Check_Trace_SHA256;

   procedure Append_Header
     (Result       : in out Unbounded_String;
      Format       : String;
      Item         : Flyology_TLA.Replay.Replay_Result;
      Trace_SHA256 : String)
   is
   begin
      Check_Trace_SHA256 (Trace_SHA256);
      Append
        (Result,
         "{""format"":" & Flyology_TLA.JSON.Quote (Format)
         & ",""verdict"":" & Flyology_TLA.JSON.Quote (Verdict_Image (Item.Status))
         & ",""trace_sha256"":" & Flyology_TLA.JSON.Quote (Trace_SHA256)
         & ",""compared_steps"":" & Natural_Image (Item.Compared_Steps)
         & ",""failure"":");
   end Append_Header;

   procedure Append_Failure_Fields
     (Result : in out Unbounded_String;
      Item   : Flyology_TLA.Replay.Replay_Result)
   is
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
      Append
        (Result,
         "{""step"":" & Natural_Image (Item.Failure_Step)
         & ",""property"":" & Flyology_TLA.JSON.Quote (Property)
         & ",""fingerprint"":" & Flyology_TLA.JSON.Quote (Fingerprint)
         & ",""detail"":" & Flyology_TLA.JSON.Quote (Detail));
   end Append_Failure_Fields;

   function Canonical_Embedded (Source : String) return String is
   begin
      if Source'Length = 0 then
         raise Constraint_Error with "result/2 observation is absent";
      end if;
      --  Observed_Comparison is private and its constructors canonicalize.
      return Source;
   end Canonical_Embedded;

   function JSON_Image
     (Item         : Flyology_TLA.Replay.Replay_Result;
      Trace_SHA256 : String) return String
   is
      Result : Unbounded_String;
   begin
      Append_Header (Result, "flyology.tla.result/1", Item, Trace_SHA256);

      if Item.Status = Flyology_TLA.Replay.Conformant then
         Append (Result, "null");
      else
         Append_Failure_Fields (Result, Item);
         Append (Result, "}");
      end if;
      Append (Result, "}");
      return To_String (Result);
   end JSON_Image;

   function JSON_Image
     (Item         : Flyology_TLA.Replay.Replay_Result_V2;
      Trace_SHA256 : String) return String
   is
      Summary : Flyology_TLA.Replay.Replay_Result renames Item.Summary;
      Kind    : constant Flyology_TLA.Replay.Observation_Kind := Item.Observed.Kind;
      Result  : Unbounded_String;
   begin
      case Summary.Status is
         when Flyology_TLA.Replay.Conformant =>
            if Kind /= Flyology_TLA.Replay.No_Observation then
               raise Constraint_Error with "conformant result/2 has an observation";
            end if;
         when Flyology_TLA.Replay.Diverged =>
            if Summary.Compared_Steps /= Summary.Failure_Step then
               raise Constraint_Error with
                 "diverged result/2 failure step is not the completed comparison";
            elsif Summary.Failure_Step = 0
              and then Kind /= Flyology_TLA.Replay.Initial_State_Observation
            then
               raise Constraint_Error with
                 "initial divergence result/2 lacks an initial-state observation";
            elsif Summary.Failure_Step > 0
              and then Kind /= Flyology_TLA.Replay.Step_Observation
            then
               raise Constraint_Error with
                 "step divergence result/2 lacks a step observation";
            end if;
         when Flyology_TLA.Replay.Adapter_Error =>
            if Kind /= Flyology_TLA.Replay.No_Observation then
               raise Constraint_Error with "adapter-error result/2 has an observation";
            elsif Summary.Failure_Step = 0 then
               if Summary.Compared_Steps /= 0 then
                  raise Constraint_Error with "reset adapter-error has compared steps";
               end if;
            elsif Summary.Failure_Step - 1 /= Summary.Compared_Steps then
               raise Constraint_Error with
                 "adapter-error result/2 failure does not follow compared steps";
            end if;
         when Flyology_TLA.Replay.Invalid_Trace =>
            if Kind /= Flyology_TLA.Replay.No_Observation
              or else Summary.Failure_Step /= 0
              or else Summary.Compared_Steps /= 0
            then
               raise Constraint_Error with
                 "invalid-trace result/2 has replay comparison state";
            end if;
      end case;

      Append_Header (Result, "flyology.tla.result/2", Summary, Trace_SHA256);
      if Summary.Status = Flyology_TLA.Replay.Conformant then
         Append (Result, "null");
      else
         Append_Failure_Fields (Result, Summary);
         if Summary.Status = Flyology_TLA.Replay.Diverged then
            Append (Result, ",""observed"":{""outcome"":");
            if Kind = Flyology_TLA.Replay.Initial_State_Observation then
               Append (Result, "null");
            else
               Append
                 (Result,
                  Canonical_Embedded
                    (Flyology_TLA.Replay.Outcome_JSON (Item.Observed)));
            end if;
            Append
              (Result,
               ",""state"":"
               & Canonical_Embedded
                   (Flyology_TLA.Replay.State_JSON (Item.Observed))
               & "}");
         end if;
         Append (Result, "}");
      end if;
      Append (Result, "}");
      return To_String (Result);
   end JSON_Image;

end Flyology_TLA.Result_Encoding;
