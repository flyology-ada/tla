with Ada.Command_Line;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Exceptions;
with Ada.Text_IO;
with Flyology_TLA.TLC_Traces;
with Flyology_TLA.Toolchains;
with Flyology_TLA.Traces;
with Flyology_TLA_Ada_Generation;

procedure Flyology_TLA_Main is

   use type Ada.Directories.File_Size;

   function Argument (Index : Positive) return String
   renames Ada.Command_Line.Argument;

   function Option_Value (Name : String; Default : String := "") return String is
      Cursor : Natural := 4;
   begin
      while Cursor < Ada.Command_Line.Argument_Count loop
         if Argument (Cursor) = Name then
            return Argument (Cursor + 1);
         end if;
         Cursor := Cursor + 2;
      end loop;
      if Default'Length > 0 then
         return Default;
      end if;
      raise Constraint_Error with "missing required option " & Name;
   end Option_Value;

   procedure Validate_Generate_Options is
      Cursor : Natural := 4;
   begin
      if (Ada.Command_Line.Argument_Count - 3) mod 2 /= 0 then
         raise Constraint_Error with "each ada generate option requires one value";
      end if;
      while Cursor < Ada.Command_Line.Argument_Count loop
         if Argument (Cursor) not in
           "--config" | "--package" | "--output" | "--type-invariant" |
           "--input-type" | "--outcome-type"
         then
            raise Constraint_Error with "unknown ada generate option " & Argument (Cursor);
         end if;
         declare
            Previous : Natural := 4;
         begin
            while Previous < Cursor loop
               if Argument (Previous) = Argument (Cursor) then
                  raise Constraint_Error
                    with "duplicate ada generate option " & Argument (Cursor);
               end if;
               Previous := Previous + 2;
            end loop;
         end;
         Cursor := Cursor + 2;
      end loop;
   end Validate_Generate_Options;

   function Limits
     (Path : String; Maximum_Steps : Positive; Maximum_Depth : Positive)
      return Flyology_TLA.Traces.Load_Limits
   is
      Size : constant Ada.Directories.File_Size := Ada.Directories.Size (Path);
   begin
      if Size = 0 or else Size > Ada.Directories.File_Size (Positive'Last) then
         raise Constraint_Error with "input file size is not supported";
      end if;
      return
        (Maximum_File_Bytes   => Positive (Size),
         Maximum_Steps        => Maximum_Steps,
         Maximum_JSON_Depth   => Maximum_Depth,
         Maximum_Object_Names => Positive (Size),
         Maximum_Name_Bytes   => Positive (Size),
         Maximum_String_Bytes => Positive (Size),
         Maximum_Value_Bytes  => Positive (Size));
   end Limits;

   procedure Help is
   begin
      Ada.Text_IO.Put_Line
        ("flyology-tla: TLA+ trace generation and Ada conformance replay");
      Ada.Text_IO.Put_Line ("usage:");
      Ada.Text_IO.Put_Line
        ("  flyology-tla trace validate TRACE MAX_STEPS MAX_JSON_DEPTH");
      Ada.Text_IO.Put_Line
        ("  flyology-tla trace normalize RAW OUT MODULE CFG SOURCE_SHA256 "
         & "TOOLCHAIN MAX_STEPS MAX_JSON_DEPTH");
      Ada.Text_IO.Put_Line
        ("  flyology-tla trace prefix TRACE OUT LAST_STEP MAX_STEPS MAX_JSON_DEPTH");
      Ada.Text_IO.Put_Line
        ("  flyology-tla ada generate MODULE.tla --config MODEL.cfg "
         & "--package ADA_PACKAGE --output DIRECTORY");
      Ada.Text_IO.Put_Line
        ("      [--type-invariant TypeOK] [--input-type HarnessInputType] "
         & "[--outcome-type HarnessOutcomeType]");
      Ada.Text_IO.Put_Line
        ("  flyology-tla toolchain install|verify|env [ABSOLUTE_ROOT]");
   end Help;

begin
   if Ada.Command_Line.Argument_Count = 0
     or else Argument (1) in "--help" | "help"
   then
      Help;
   elsif Ada.Command_Line.Argument_Count = 5
     and then Argument (1) = "trace"
     and then Argument (2) = "validate"
   then
      declare
         Maximum_Steps : constant Positive := Positive'Value (Argument (4));
         Maximum_Depth : constant Positive := Positive'Value (Argument (5));
         Trace : constant Flyology_TLA.Traces.Trace :=
           Flyology_TLA.Traces.Load
             (Argument (3), Limits (Argument (3), Maximum_Steps, Maximum_Depth));
      begin
         Ada.Text_IO.Put_Line
           ("valid flyology.tla.trace/1:"
            & Natural'Image (Natural (Trace.Steps.Length))
            & " steps");
      end;
   elsif Ada.Command_Line.Argument_Count = 10
     and then Argument (1) = "trace"
     and then Argument (2) = "normalize"
   then
      declare
         Maximum_Steps : constant Positive := Positive'Value (Argument (9));
         Maximum_Depth : constant Positive := Positive'Value (Argument (10));
      begin
         Flyology_TLA.TLC_Traces.Normalize
           (Raw_Path           => Argument (3),
            Output_Path        => Argument (4),
            Module_Name        => Argument (5),
            Configuration      => Argument (6),
            Source_SHA256      => Argument (7),
            Toolchain_Identity => Argument (8),
            Limits             => Limits (Argument (3), Maximum_Steps, Maximum_Depth));
         Ada.Text_IO.Put_Line ("normalized flyology.tla.trace/1: " & Argument (4));
      end;
   elsif Ada.Command_Line.Argument_Count = 7
     and then Argument (1) = "trace"
     and then Argument (2) = "prefix"
   then
      declare
         Last_Step    : constant Natural := Natural'Value (Argument (5));
         Maximum_Steps : constant Positive := Positive'Value (Argument (6));
         Maximum_Depth : constant Positive := Positive'Value (Argument (7));
         Trace : constant Flyology_TLA.Traces.Trace :=
           Flyology_TLA.Traces.Load
             (Argument (3), Limits (Argument (3), Maximum_Steps, Maximum_Depth));
      begin
         Flyology_TLA.Traces.Write_Prefix (Trace, Last_Step, Argument (4));
         Ada.Text_IO.Put_Line
           ("wrote flyology.tla.trace/1 prefix through step"
            & Natural'Image (Last_Step)
            & ": "
            & Argument (4));
      end;
   elsif Ada.Command_Line.Argument_Count >= 9
     and then Argument (1) = "ada"
     and then Argument (2) = "generate"
   then
      Validate_Generate_Options;
      declare
         Package_Name : constant String := Option_Value ("--package");
         Output_Path  : constant String := Option_Value ("--output");
      begin
         Flyology_TLA_Ada_Generation.Generate
           (Module_Path           => Argument (3),
            Configuration_Path    => Option_Value ("--config"),
            Type_Invariant        => Option_Value ("--type-invariant", "TypeOK"),
            Input_Type_Operator   => Option_Value ("--input-type", "HarnessInputType"),
            Outcome_Type_Operator => Option_Value
              ("--outcome-type", "HarnessOutcomeType"),
            Package_Name          => Package_Name,
            Output_Directory      => Output_Path,
            Java_Path             => Ada.Environment_Variables.Value ("FLYOLOGY_TLA_JAVA"),
            TLC_Jar_Path          => Ada.Environment_Variables.Value ("FLYOLOGY_TLA_TLC_JAR"));
         Ada.Text_IO.Put_Line
           ("generated typed Ada harness package " & Package_Name & " in " & Output_Path);
      end;
   elsif Ada.Command_Line.Argument_Count in 2 .. 3
     and then Argument (1) = "toolchain"
     and then Argument (2) in "install" | "verify" | "env"
   then
      Flyology_TLA.Toolchains.Dispatch;
   else
      Help;
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
exception
   when Error : others =>
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "flyology-tla: " & Ada.Exceptions.Exception_Message (Error));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
end Flyology_TLA_Main;
