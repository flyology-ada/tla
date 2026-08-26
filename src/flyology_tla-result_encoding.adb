with Ada.Strings;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Flyology_TLA.JSON;

package body Flyology_TLA.Result_Encoding is

   use Ada.Strings.Unbounded;
   use type Flyology_TLA.Replay.Verdict;

   function JSON_Image
     (Item         : Flyology_TLA.Replay.Replay_Result;
      Trace_SHA256 : String) return String
   is
      Verdict_Text : constant String :=
        (case Item.Status is
           when Flyology_TLA.Replay.Conformant    => "conformant",
           when Flyology_TLA.Replay.Diverged      => "diverged",
           when Flyology_TLA.Replay.Adapter_Error => "adapter-error",
           when Flyology_TLA.Replay.Invalid_Trace => "invalid-trace");
      Result : Unbounded_String;
   begin
      if Trace_SHA256'Length /= 64
        or else
          (for some Character_Of_SHA of Trace_SHA256 =>
             Character_Of_SHA not in '0' .. '9' | 'a' .. 'f')
      then
         raise Constraint_Error with
           "trace SHA-256 is not canonical lowercase hexadecimal";
      end if;

      Append
        (Result,
         "{""format"":""flyology.tla.result/1"",""verdict"":"
         & Flyology_TLA.JSON.Quote (Verdict_Text)
         & ",""trace_sha256"":"
         & Flyology_TLA.JSON.Quote (Trace_SHA256)
         & ",""compared_steps"":"
         & Ada.Strings.Fixed.Trim
             (Natural'Image (Item.Compared_Steps), Ada.Strings.Both)
         & ",""failure"":" );

      if Item.Status = Flyology_TLA.Replay.Conformant then
         Append (Result, "null");
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
            Append
              (Result,
               "{""step"":"
               & Ada.Strings.Fixed.Trim
                   (Natural'Image (Item.Failure_Step), Ada.Strings.Both)
               & ",""property"":"
               & Flyology_TLA.JSON.Quote (Property)
               & ",""fingerprint"":"
               & Flyology_TLA.JSON.Quote (Fingerprint)
               & ",""detail"":"
               & Flyology_TLA.JSON.Quote (Detail)
               & "}");
         end;
      end if;
      Append (Result, "}");
      return To_String (Result);
   end JSON_Image;

end Flyology_TLA.Result_Encoding;
