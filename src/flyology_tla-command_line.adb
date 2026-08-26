with Ada.Command_Line;
with Ada.Text_IO;
with Flyology_TLA.Reporting;
with GNAT.OS_Lib;

package body Flyology_TLA.Command_Line is

   use Ada.Strings.Unbounded;
   use type Flyology_TLA.Replay.Verdict;

   function Safe_Diagnostic (Value : String) return String is
      Hex    : constant String := "0123456789abcdef";
      Result : Unbounded_String;
   begin
      --  Command names, paths, and exception messages can contain control
      --  bytes. Keep every diagnostic on the line chosen by the caller.
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
   end Safe_Diagnostic;

   function Flag (Name : String; Description : String) return Application_Flag is
      function Is_Built_In return Boolean is
        (Name in
           "--help" | "--format" | "--result-json" | "--max-file-bytes" |
           "--max-steps" | "--max-json-depth" | "--max-object-names" |
           "--max-name-bytes" | "--max-string-bytes" | "--max-value-bytes");
   begin
      if Name'Length < 3
        or else Name (Name'First .. Name'First + 1) /= "--"
        or else Name = "--"
        or else Name (Name'First + 2) not in 'a' .. 'z'
        or else Name (Name'Last) = '-'
        or else
          (for some Item of Name (Name'First + 2 .. Name'Last) =>
             Item not in 'a' .. 'z' | '0' .. '9' | '-')
      then
         raise Constraint_Error with "invalid application --long-option flag";
      elsif Is_Built_In then
         raise Constraint_Error with "application flag collides with built-in " & Name;
      elsif Description'Length = 0
        or else
          (for some Item of Description =>
             Character'Pos (Item) < 32 or else Character'Pos (Item) = 127)
      then
         raise Constraint_Error with "application flag description is empty or unsafe";
      end if;
      return
        (Name        => To_Unbounded_String (Name),
         Description => To_Unbounded_String (Description),
         Present     => False);
   end Flag;

   function Is_Set (Item : Application_Flag) return Boolean is (Item.Present);

   procedure Mark (Seen : in out Boolean; Name : String) is
   begin
      if Seen then
         raise Usage_Error with "duplicate option " & Name;
      end if;
      Seen := True;
   end Mark;

   function Positive_Value (Value : String; Name : String) return Positive is
   begin
      if Value'Length = 0
        or else (for some Item of Value => Item not in '0' .. '9')
      then
         raise Usage_Error with Name & " requires a positive decimal integer";
      end if;
      return Positive'Value (Value);
   exception
      when Constraint_Error =>
         raise Usage_Error with Name & " requires a supported positive decimal integer";
   end Positive_Value;

   function Parse_Internal
     (Default_Limits    : Flyology_TLA.Traces.Load_Limits;
      Application_Flags : in out Application_Flag_Array) return Configuration
   is
      Result            : Configuration :=
        (Input_Path      => Null_Unbounded_String,
         JSON_Path       => Null_Unbounded_String,
         Selected_Format => Terse_Output,
         Selected_Limits => Default_Limits,
         Trace_SHA256    => Null_Unbounded_String,
         Show_Help       => False);
      Cursor            : Positive := 1;
      End_Of_Options     : Boolean := False;
      Format_Seen        : Boolean := False;
      JSON_Path_Seen     : Boolean := False;
      Maximum_File_Seen  : Boolean := False;
      Maximum_Steps_Seen : Boolean := False;
      Maximum_Depth_Seen : Boolean := False;
      Maximum_Objects_Seen : Boolean := False;
      Maximum_Name_Seen  : Boolean := False;
      Maximum_String_Seen : Boolean := False;
      Maximum_Value_Seen : Boolean := False;
      Help_Seen          : Boolean := False;

      function Value_After (Name : String) return String is
      begin
         if Cursor = Ada.Command_Line.Argument_Count then
            raise Usage_Error with "option " & Name & " requires one value";
         end if;
         return Ada.Command_Line.Argument (Cursor + 1);
      end Value_After;

      function Handle_Application_Flag (Name : String) return Boolean is
      begin
         for Item of Application_Flags loop
            if To_String (Item.Name) = Name then
               if Item.Present then
                  raise Usage_Error with "duplicate option " & Name;
               end if;
               Item.Present := True;
               return True;
            end if;
         end loop;
         return False;
      end Handle_Application_Flag;

   begin
      for Left in Application_Flags'Range loop
         Application_Flags (Left).Present := False;
         for Right in Application_Flags'Range loop
            if Left /= Right
              and then Application_Flags (Left).Name = Application_Flags (Right).Name
            then
               raise Constraint_Error with
                 "duplicate registered application flag "
                 & To_String (Application_Flags (Left).Name);
            end if;
         end loop;
      end loop;

      while Cursor <= Ada.Command_Line.Argument_Count loop
         declare
            Argument : constant String := Ada.Command_Line.Argument (Cursor);
         begin
            if not End_Of_Options and then Argument = "--" then
               End_Of_Options := True;
               Cursor := Cursor + 1;
            elsif not End_Of_Options and then Argument = "--help" then
               Mark (Help_Seen, Argument);
               Result.Show_Help := True;
               Cursor := Cursor + 1;
            elsif not End_Of_Options and then Argument = "--format" then
               Mark (Format_Seen, Argument);
               declare
                  Value : constant String := Value_After (Argument);
               begin
                  if Value = "terse" then
                     Result.Selected_Format := Terse_Output;
                  elsif Value = "verbose" then
                     Result.Selected_Format := Verbose_Output;
                  elsif Value = "json" then
                     Result.Selected_Format := JSON_Output;
                  else
                     raise Usage_Error with
                       "--format must be terse, verbose, or json";
                  end if;
               end;
               Cursor := Cursor + 2;
            elsif not End_Of_Options and then Argument = "--result-json" then
               Mark (JSON_Path_Seen, Argument);
               Result.JSON_Path := To_Unbounded_String (Value_After (Argument));
               if Length (Result.JSON_Path) = 0 then
                  raise Usage_Error with "--result-json path is empty";
               end if;
               Cursor := Cursor + 2;
            elsif not End_Of_Options and then Argument = "--max-file-bytes" then
               Mark (Maximum_File_Seen, Argument);
               Result.Selected_Limits.Maximum_File_Bytes :=
                 Positive_Value (Value_After (Argument), Argument);
               Cursor := Cursor + 2;
            elsif not End_Of_Options and then Argument = "--max-steps" then
               Mark (Maximum_Steps_Seen, Argument);
               Result.Selected_Limits.Maximum_Steps :=
                 Positive_Value (Value_After (Argument), Argument);
               Cursor := Cursor + 2;
            elsif not End_Of_Options and then Argument = "--max-json-depth" then
               Mark (Maximum_Depth_Seen, Argument);
               Result.Selected_Limits.Maximum_JSON_Depth :=
                 Positive_Value (Value_After (Argument), Argument);
               Cursor := Cursor + 2;
            elsif not End_Of_Options and then Argument = "--max-object-names" then
               Mark (Maximum_Objects_Seen, Argument);
               Result.Selected_Limits.Maximum_Object_Names :=
                 Positive_Value (Value_After (Argument), Argument);
               Cursor := Cursor + 2;
            elsif not End_Of_Options and then Argument = "--max-name-bytes" then
               Mark (Maximum_Name_Seen, Argument);
               Result.Selected_Limits.Maximum_Name_Bytes :=
                 Positive_Value (Value_After (Argument), Argument);
               Cursor := Cursor + 2;
            elsif not End_Of_Options and then Argument = "--max-string-bytes" then
               Mark (Maximum_String_Seen, Argument);
               Result.Selected_Limits.Maximum_String_Bytes :=
                 Positive_Value (Value_After (Argument), Argument);
               Cursor := Cursor + 2;
            elsif not End_Of_Options and then Argument = "--max-value-bytes" then
               Mark (Maximum_Value_Seen, Argument);
               Result.Selected_Limits.Maximum_Value_Bytes :=
                 Positive_Value (Value_After (Argument), Argument);
               Cursor := Cursor + 2;
            elsif not End_Of_Options
              and then Argument'Length >= 2
              and then Argument (Argument'First .. Argument'First + 1) = "--"
            then
               if not Handle_Application_Flag (Argument) then
                  raise Usage_Error with "unknown option " & Argument;
               end if;
               Cursor := Cursor + 1;
            else
               if Length (Result.Input_Path) > 0 then
                  raise Usage_Error with "exactly one TRACE path is required";
               end if;
               Result.Input_Path := To_Unbounded_String (Argument);
               Cursor := Cursor + 1;
            end if;
         end;
      end loop;

      if not Result.Show_Help and then Length (Result.Input_Path) = 0 then
         raise Usage_Error with "exactly one TRACE path is required";
      elsif Length (Result.JSON_Path) > 0 then
         declare
            Input_Name : constant String := To_String (Result.Input_Path);
            JSON_Name  : constant String := To_String (Result.JSON_Path);
            Same_Path  : Boolean := Input_Name = JSON_Name;
         begin
            if not Same_Path then
               declare
                  Normal_Input : constant String :=
                    GNAT.OS_Lib.Normalize_Pathname
                      (Input_Name, Resolve_Links => True);
                  Normal_JSON : constant String :=
                    GNAT.OS_Lib.Normalize_Pathname
                      (JSON_Name, Resolve_Links => True);
               begin
                  Same_Path :=
                    Normal_Input'Length > 0
                    and then Normal_JSON'Length > 0
                    and then Normal_Input = Normal_JSON;
               end;
            end if;
            if Same_Path then
               raise Usage_Error with "--result-json must not overwrite TRACE";
            end if;
         end;
      end if;
      return Result;
   end Parse_Internal;

   function Parse
     (Default_Limits : Flyology_TLA.Traces.Load_Limits) return Configuration
   is
      No_Application_Flags : Application_Flag_Array (1 .. 0);
   begin
      return Parse_Internal (Default_Limits, No_Application_Flags);
   end Parse;

   function Parse
     (Default_Limits    : Flyology_TLA.Traces.Load_Limits;
      Application_Flags : in out Application_Flag_Array) return Configuration is
     (Parse_Internal (Default_Limits, Application_Flags));

   function Help_Requested (Item : Configuration) return Boolean is
     (Item.Show_Help);

   function Trace_Path (Item : Configuration) return String is
     (To_String (Item.Input_Path));

   function Limits
     (Item : Configuration) return Flyology_TLA.Traces.Load_Limits is
     (Item.Selected_Limits);

   function Format (Item : Configuration) return Output_Format is
     (Item.Selected_Format);

   function Result_JSON_Path (Item : Configuration) return String is
     (To_String (Item.JSON_Path));

   function Load
     (Item : in out Configuration) return Flyology_TLA.Traces.Trace
   is
   begin
      return
        Flyology_TLA.Traces.Load
          (To_String (Item.Input_Path),
           Item.Selected_Limits,
           Item.Trace_SHA256);
   end Load;

   procedure Report
     (Config : Configuration;
      Result : Flyology_TLA.Replay.Replay_Result)
   is
      Needs_JSON : constant Boolean :=
        Config.Selected_Format = JSON_Output or else Length (Config.JSON_Path) > 0;
   begin
      if Needs_JSON and then Length (Config.Trace_SHA256) = 0 then
         raise Program_Error with
           "cannot report JSON before loading the configured trace";
      end if;
      --  Materialize a requested evidence artifact before announcing the
      --  result on stdout. A sidecar I/O failure must not look successful.
      if Length (Config.JSON_Path) > 0 then
         Flyology_TLA.Reporting.Write_JSON
           (Result,
            To_String (Config.Trace_SHA256),
            To_String (Config.JSON_Path));
      end if;
      case Config.Selected_Format is
         when Terse_Output =>
            Flyology_TLA.Reporting.Put (Result, Flyology_TLA.Reporting.Terse);
         when Verbose_Output =>
            Flyology_TLA.Reporting.Put (Result, Flyology_TLA.Reporting.Verbose);
         when JSON_Output =>
            Flyology_TLA.Reporting.Put_JSON
              (Result, To_String (Config.Trace_SHA256));
      end case;
   end Report;

   procedure Report
     (Config : Configuration;
      Result : Flyology_TLA.Replay.Replay_Result_V2)
   is
      Needs_JSON : constant Boolean :=
        Config.Selected_Format = JSON_Output or else Length (Config.JSON_Path) > 0;
   begin
      if Needs_JSON and then Length (Config.Trace_SHA256) = 0 then
         raise Program_Error with
           "cannot report JSON before loading the configured trace";
      end if;
      if Length (Config.JSON_Path) > 0 then
         Flyology_TLA.Reporting.Write_JSON
           (Result,
            To_String (Config.Trace_SHA256),
            To_String (Config.JSON_Path));
      end if;
      case Config.Selected_Format is
         when Terse_Output =>
            Flyology_TLA.Reporting.Put (Result, Flyology_TLA.Reporting.Terse);
         when Verbose_Output =>
            Flyology_TLA.Reporting.Put (Result, Flyology_TLA.Reporting.Verbose);
         when JSON_Output =>
            Flyology_TLA.Reporting.Put_JSON
              (Result, To_String (Config.Trace_SHA256));
      end case;
   end Report;

   procedure Set_Exit_Status (Result : Flyology_TLA.Replay.Replay_Result) is
   begin
      Ada.Command_Line.Set_Exit_Status
        (if Result.Status = Flyology_TLA.Replay.Conformant
         then Ada.Command_Line.Success
         else Ada.Command_Line.Failure);
   end Set_Exit_Status;

   procedure Set_Exit_Status
     (Result : Flyology_TLA.Replay.Replay_Result_V2) is
   begin
      Set_Exit_Status (Result.Summary);
   end Set_Exit_Status;

   procedure Put_Help_To
     (File              : Ada.Text_IO.File_Type;
      Application_Flags : Application_Flag_Array)
   is
   begin
      Ada.Text_IO.Put_Line
        (File,
         "usage: " & Safe_Diagnostic (Ada.Command_Line.Command_Name)
         & " [OPTIONS] TRACE");
      Ada.Text_IO.Put_Line (File, "options:");
      Ada.Text_IO.Put_Line
        (File, "  --format terse|verbose|json   stdout format (default: terse)");
      Ada.Text_IO.Put_Line
        (File, "  --result-json PATH            also write selected result contract JSON");
      Ada.Text_IO.Put_Line (File, "  --max-file-bytes N");
      Ada.Text_IO.Put_Line (File, "  --max-steps N");
      Ada.Text_IO.Put_Line (File, "  --max-json-depth N");
      Ada.Text_IO.Put_Line (File, "  --max-object-names N");
      Ada.Text_IO.Put_Line (File, "  --max-name-bytes N");
      Ada.Text_IO.Put_Line (File, "  --max-string-bytes N");
      Ada.Text_IO.Put_Line (File, "  --max-value-bytes N");
      for Item of Application_Flags loop
         Ada.Text_IO.Put_Line
           (File,
            "  " & To_String (Item.Name) & "   " & To_String (Item.Description));
      end loop;
      Ada.Text_IO.Put_Line (File, "  --help");
   end Put_Help_To;

   procedure Put_Help is
      No_Application_Flags : Application_Flag_Array (1 .. 0);
   begin
      Put_Help_To (Ada.Text_IO.Standard_Output, No_Application_Flags);
   end Put_Help;

   procedure Put_Help (Application_Flags : Application_Flag_Array) is
   begin
      Put_Help_To (Ada.Text_IO.Standard_Output, Application_Flags);
   end Put_Help;

   procedure Fail (Message : String; Show_Help : Boolean := False) is
      No_Application_Flags : Application_Flag_Array (1 .. 0);
   begin
      Fail (Message, No_Application_Flags, Show_Help);
   end Fail;

   procedure Fail
     (Message           : String;
      Application_Flags : Application_Flag_Array;
      Show_Help         : Boolean := False)
   is
   begin
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         Safe_Diagnostic (Ada.Command_Line.Command_Name)
         & ": " & Safe_Diagnostic (Message));
      if Show_Help then
         Put_Help_To (Ada.Text_IO.Standard_Error, Application_Flags);
      end if;
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end Fail;

end Flyology_TLA.Command_Line;
