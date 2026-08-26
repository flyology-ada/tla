with Ada.Exceptions;
with Ada.Strings;
with Ada.Strings.Fixed;
with Ada.Text_IO;
with Flyology_TLA.JSON;

package body Flyology_TLA.TLC_Traces is

   function Is_Identifier (Value : String) return Boolean is
     (Value'Length > 0
      and then Value (Value'First) in 'A' .. 'Z' | 'a' .. 'z' | '_'
      and then
        (for all Item of Value => Item in 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '_'));

   function Is_Lower_Hex_SHA256 (Value : String) return Boolean is
     (Value'Length = 64
      and then (for all Item of Value => Item in '0' .. '9' | 'a' .. 'f'));

   function Is_Qualified_Action (Value : String) return Boolean is
      Separator : Natural := 0;
   begin
      for Index in Value'Range loop
         if Value (Index) = '!' then
            if Separator /= 0 then
               return False;
            end if;
            Separator := Index;
         end if;
      end loop;
      return Separator > Value'First
        and then Separator < Value'Last
        and then Is_Identifier (Value (Value'First .. Separator - 1))
        and then Is_Identifier (Value (Separator + 1 .. Value'Last));
   end Is_Qualified_Action;

   function Qualified (Module_Name : String; Action : String) return String is
   begin
      if (for some Item of Action => Item = '!') then
         return Action;
      end if;
      return Module_Name & "!" & Action;
   end Qualified;

   procedure Normalize
     (Raw_Path           : String;
      Output_Path        : String;
      Module_Name        : String;
      Configuration      : String;
      Source_SHA256      : String;
      Configuration_SHA256 : String;
      Toolchain_Identity : String;
      Limits             : Flyology_TLA.Traces.Load_Limits)
   is
      Source : constant String :=
        Flyology_TLA.JSON.Read_File (Raw_Path, Limits.Maximum_File_Bytes);
      Root   : Flyology_TLA.JSON.Value;
      States : Flyology_TLA.JSON.Value;
      Output : Ada.Text_IO.File_Type;
   begin
      Flyology_TLA.JSON.Validate
        (Source,
         Limits.Maximum_JSON_Depth,
         Limits.Maximum_Name_Bytes,
         Limits.Maximum_Object_Names);
      Root := Flyology_TLA.JSON.Root (Source);
      States := Flyology_TLA.JSON.Member
        (Source,
         Flyology_TLA.JSON.Member (Source, Root, "counterexample"),
         "state");
      if Flyology_TLA.JSON.Length (Source, States) = 0 then
         raise Flyology_TLA.Traces.Trace_Error with "TLC counterexample has no states";
      elsif Flyology_TLA.JSON.Length (Source, States) - 1 > Limits.Maximum_Steps then
         raise Flyology_TLA.Traces.Trace_Error with "TLC trace exceeds caller step limit";
      end if;
      if not Is_Identifier (Module_Name) then
         raise Flyology_TLA.Traces.Trace_Error with "module is not a TLA+ identifier";
      elsif Configuration'Length = 0 or else Toolchain_Identity'Length = 0 then
         raise Flyology_TLA.Traces.Trace_Error with "configuration or toolchain identity is empty";
      elsif not Is_Lower_Hex_SHA256 (Source_SHA256) then
         raise Flyology_TLA.Traces.Trace_Error with "source SHA-256 is not canonical";
      elsif not Is_Lower_Hex_SHA256 (Configuration_SHA256) then
         raise Flyology_TLA.Traces.Trace_Error with
           "configuration SHA-256 is not canonical";
      elsif Module_Name'Length > Limits.Maximum_String_Bytes
        or else Configuration'Length > Limits.Maximum_String_Bytes
        or else Toolchain_Identity'Length > Limits.Maximum_String_Bytes
      then
         raise Flyology_TLA.Traces.Trace_Error with "normalization metadata exceeds caller limit";
      end if;
      declare
         State_Count : constant Natural := Flyology_TLA.JSON.Length (Source, States);
         First_Envelope : constant Flyology_TLA.JSON.Value :=
           Flyology_TLA.JSON.Element (Source, States, 0);
         Initial : constant Flyology_TLA.JSON.Value :=
           Flyology_TLA.JSON.Element (Source, First_Envelope, 1);
         Initial_State : constant String :=
           Flyology_TLA.JSON.Canonical_Image
             (Source, Flyology_TLA.JSON.Member (Source, Initial, "state"));
      begin
         if Flyology_TLA.JSON.Length (Source, First_Envelope) /= 2 then
            raise Flyology_TLA.Traces.Trace_Error with "TLC initial state envelope is not [ordinal, alias]";
         elsif Flyology_TLA.JSON.Natural_Data
           (Source, Flyology_TLA.JSON.Element (Source, First_Envelope, 0)) /= 1
         then
            raise Flyology_TLA.Traces.Trace_Error with "TLC state numbering does not begin at one";
         end if;
         if Initial_State'Length > Limits.Maximum_Value_Bytes then
            raise Flyology_TLA.Traces.Trace_Error with "TLC initial state exceeds caller value limit";
         end if;
         if State_Count > 1 then
            for Offset in 1 .. State_Count - 1 loop
               declare
                  Envelope : constant Flyology_TLA.JSON.Value :=
                    Flyology_TLA.JSON.Element (Source, States, Offset);
                  Alias : constant Flyology_TLA.JSON.Value :=
                    Flyology_TLA.JSON.Element (Source, Envelope, 1);
                  Action : constant String :=
                    Flyology_TLA.JSON.String_Data
                      (Source, Flyology_TLA.JSON.Member (Source, Alias, "action"));
                  Qualified_Action : constant String := Qualified (Module_Name, Action);
                  Model_Source : constant String :=
                    (if Flyology_TLA.JSON.Has_Member (Source, Alias, "model_source")
                     then Qualified
                       (Module_Name,
                        Flyology_TLA.JSON.String_Data
                          (Source, Flyology_TLA.JSON.Member (Source, Alias, "model_source")))
                     else Qualified_Action);
                  Role : constant String :=
                    (if Flyology_TLA.JSON.Has_Member (Source, Alias, "role")
                     then Flyology_TLA.JSON.String_Data
                       (Source, Flyology_TLA.JSON.Member (Source, Alias, "role"))
                     else Action);
                  Input : constant String :=
                    Flyology_TLA.JSON.Canonical_Image
                      (Source, Flyology_TLA.JSON.Member (Source, Alias, "input"));
                  Outcome : constant String :=
                    Flyology_TLA.JSON.Canonical_Image
                      (Source, Flyology_TLA.JSON.Member (Source, Alias, "outcome"));
                  State : constant String :=
                    Flyology_TLA.JSON.Canonical_Image
                      (Source, Flyology_TLA.JSON.Member (Source, Alias, "state"));
               begin
                  if Flyology_TLA.JSON.Length (Source, Envelope) /= 2 then
                     raise Flyology_TLA.Traces.Trace_Error with
                       "TLC state envelope is not [ordinal, alias]";
                  elsif Flyology_TLA.JSON.Natural_Data
                    (Source, Flyology_TLA.JSON.Element (Source, Envelope, 0)) /= Offset + 1
                  then
                     raise Flyology_TLA.Traces.Trace_Error with
                       "TLC state numbering is not contiguous";
                  elsif not Is_Qualified_Action (Qualified_Action)
                    or else not Is_Qualified_Action (Model_Source)
                  then
                     raise Flyology_TLA.Traces.Trace_Error with
                       "TLC action or model_source is not a qualified identifier";
                  end if;
                  if Role'Length = 0
                    or else Qualified_Action'Length > Limits.Maximum_String_Bytes
                    or else Model_Source'Length > Limits.Maximum_String_Bytes
                    or else Role'Length > Limits.Maximum_String_Bytes
                  then
                     raise Flyology_TLA.Traces.Trace_Error with "TLC action metadata exceeds caller limit";
                  elsif Input'Length > Limits.Maximum_Value_Bytes
                    or else Outcome'Length > Limits.Maximum_Value_Bytes
                    or else State'Length > Limits.Maximum_Value_Bytes
                  then
                     raise Flyology_TLA.Traces.Trace_Error with "TLC projected value exceeds caller limit";
                  end if;
               end;
            end loop;
         end if;
         Ada.Text_IO.Create (Output, Ada.Text_IO.Out_File, Output_Path);
         Ada.Text_IO.Put
           (Output,
            "{""format"":""flyology.tla.trace/2"",""model"":{""module"":"
            & Flyology_TLA.JSON.Quote (Module_Name)
            & ",""configuration"":"
            & Flyology_TLA.JSON.Quote (Configuration)
            & ",""source_sha256"":"
            & Flyology_TLA.JSON.Quote (Source_SHA256)
            & ",""configuration_sha256"":"
            & Flyology_TLA.JSON.Quote (Configuration_SHA256)
            & ",""toolchain"":"
            & Flyology_TLA.JSON.Quote (Toolchain_Identity)
            & "},""initial"":{""state"":"
            & Initial_State
            & "},""steps"":[");
         if State_Count > 1 then
            for Offset in 1 .. State_Count - 1 loop
               declare
               Envelope : constant Flyology_TLA.JSON.Value :=
                 Flyology_TLA.JSON.Element (Source, States, Offset);
               Alias : constant Flyology_TLA.JSON.Value :=
                 Flyology_TLA.JSON.Element (Source, Envelope, 1);
               Action : constant String :=
                 Flyology_TLA.JSON.String_Data
                   (Source, Flyology_TLA.JSON.Member (Source, Alias, "action"));
               Qualified_Action : constant String := Qualified (Module_Name, Action);
               Model_Source : constant String :=
                 (if Flyology_TLA.JSON.Has_Member (Source, Alias, "model_source")
                  then Qualified
                    (Module_Name,
                     Flyology_TLA.JSON.String_Data
                       (Source, Flyology_TLA.JSON.Member (Source, Alias, "model_source")))
                  else Qualified_Action);
               Role : constant String :=
                 (if Flyology_TLA.JSON.Has_Member (Source, Alias, "role")
                  then Flyology_TLA.JSON.String_Data
                    (Source, Flyology_TLA.JSON.Member (Source, Alias, "role"))
                  else Action);
               Input : constant String :=
                 Flyology_TLA.JSON.Canonical_Image
                   (Source, Flyology_TLA.JSON.Member (Source, Alias, "input"));
               Outcome : constant String :=
                 Flyology_TLA.JSON.Canonical_Image
                   (Source, Flyology_TLA.JSON.Member (Source, Alias, "outcome"));
               State : constant String :=
                 Flyology_TLA.JSON.Canonical_Image
                   (Source, Flyology_TLA.JSON.Member (Source, Alias, "state"));
               begin
                  if Offset > 1 then
                     Ada.Text_IO.Put (Output, ',');
                  end if;
                  Ada.Text_IO.Put
                    (Output,
                  "{""index"":"
                  & Ada.Strings.Fixed.Trim (Natural'Image (Offset), Ada.Strings.Both)
                  & ",""action"":"
                  & Flyology_TLA.JSON.Quote (Qualified_Action)
                  & ",""role"":"
                  & Flyology_TLA.JSON.Quote (Role)
                  & ",""input"":"
                  & Input
                  & ",""expected"":{""outcome"":"
                  & Outcome
                  & ",""state"":"
                  & State
                  & "},""model_source"":"
                  & Flyology_TLA.JSON.Quote (Model_Source)
                     & "}");
               end;
            end loop;
         end if;
         Ada.Text_IO.Put_Line (Output, "]}");
         Ada.Text_IO.Close (Output);
      exception
         when others =>
            if Ada.Text_IO.Is_Open (Output) then
               Ada.Text_IO.Close (Output);
            end if;
            raise;
      end;
   exception
      when Error : Flyology_TLA.JSON.JSON_Error =>
         raise Flyology_TLA.Traces.Trace_Error with Ada.Exceptions.Exception_Message (Error);
   end Normalize;

end Flyology_TLA.TLC_Traces;
