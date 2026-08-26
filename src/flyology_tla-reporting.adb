with Ada.Strings;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Flyology_TLA.Result_Encoding;

package body Flyology_TLA.Reporting is

   use Ada.Strings.Unbounded;
   use type Flyology_TLA.Replay.Verdict;

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
        when Flyology_TLA.Replay.Adapter_Error => "adapter-error");

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

   function JSON_Image
     (Result       : Flyology_TLA.Replay.Replay_Result;
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
     (File   : Ada.Text_IO.File_Type;
      Result : Flyology_TLA.Replay.Replay_Result;
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
     (File         : Ada.Text_IO.File_Type;
      Result       : Flyology_TLA.Replay.Replay_Result;
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

end Flyology_TLA.Reporting;
