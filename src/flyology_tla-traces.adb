with Ada.Exceptions;
with Ada.Strings;
with Ada.Strings.Fixed;
with Ada.Text_IO;
with Flyology_TLA.JSON;

package body Flyology_TLA.Traces is

   use Ada.Strings.Unbounded;
   use type Flyology_TLA.JSON.Value_Kind;

   procedure Check_String
     (Value : String; Limit : Positive; Label : String)
   is
   begin
      if Value'Length = 0 then
         raise Trace_Error with Label & " is empty";
      elsif Value'Length > Limit then
         raise Trace_Error with Label & " exceeds caller limit";
      end if;
   end Check_String;

   function Is_Lower_Hex_SHA256 (Value : String) return Boolean is
   begin
      if Value'Length /= 64 then
         return False;
      end if;
      return (for all Item of Value => Item in '0' .. '9' | 'a' .. 'f');
   end Is_Lower_Hex_SHA256;

   function Is_Identifier (Value : String) return Boolean is
   begin
      return Value'Length > 0
        and then Value (Value'First) in 'A' .. 'Z' | 'a' .. 'z' | '_'
        and then
          (for all Item of Value => Item in 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '_');
   end Is_Identifier;

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

   function Load (Path : String; Limits : Load_Limits) return Trace is
      Source : constant String :=
        Flyology_TLA.JSON.Read_File (Path, Limits.Maximum_File_Bytes);
      Root   : Flyology_TLA.JSON.Value;
      Result : Trace;
   begin
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
         Model_Node : constant Flyology_TLA.JSON.Value :=
           Flyology_TLA.JSON.Member (Source, Root, "model");
         Initial_Node : constant Flyology_TLA.JSON.Value :=
           Flyology_TLA.JSON.Member (Source, Root, "initial");
         Steps_Node : constant Flyology_TLA.JSON.Value :=
           Flyology_TLA.JSON.Member (Source, Root, "steps");
         Module_Name : constant String :=
           Flyology_TLA.JSON.String_Data
             (Source, Flyology_TLA.JSON.Member (Source, Model_Node, "module"));
         Configuration : constant String :=
           Flyology_TLA.JSON.String_Data
             (Source, Flyology_TLA.JSON.Member (Source, Model_Node, "configuration"));
         Source_SHA256 : constant String :=
           Flyology_TLA.JSON.String_Data
             (Source, Flyology_TLA.JSON.Member (Source, Model_Node, "source_sha256"));
         Toolchain : constant String :=
           Flyology_TLA.JSON.String_Data
             (Source, Flyology_TLA.JSON.Member (Source, Model_Node, "toolchain"));
         Step_Count : constant Natural := Flyology_TLA.JSON.Length (Source, Steps_Node);
      begin
         if Format /= "flyology.tla.trace/1" then
            raise Trace_Error with "unsupported trace format";
         elsif Flyology_TLA.JSON.Object_Length (Source, Root) /= 4
           or else Flyology_TLA.JSON.Object_Length (Source, Model_Node) /= 4
           or else Flyology_TLA.JSON.Object_Length (Source, Initial_Node) /= 1
         then
            raise Trace_Error with "trace envelope has unknown or missing members";
         elsif Flyology_TLA.JSON.Kind (Model_Node) /= Flyology_TLA.JSON.Object_Value
           or else Flyology_TLA.JSON.Kind (Initial_Node) /= Flyology_TLA.JSON.Object_Value
           or else Flyology_TLA.JSON.Kind (Steps_Node) /= Flyology_TLA.JSON.Array_Value
         then
            raise Trace_Error with "trace envelope has invalid member types";
         elsif not Is_Identifier (Module_Name) then
            raise Trace_Error with "model module is not a TLA+ identifier";
         elsif not Is_Lower_Hex_SHA256 (Source_SHA256) then
            raise Trace_Error with "model source_sha256 is not canonical";
         elsif Step_Count > Limits.Maximum_Steps then
            raise Trace_Error with "trace step count exceeds caller limit";
         end if;
         Check_String (Module_Name, Limits.Maximum_String_Bytes, "model module");
         Check_String (Configuration, Limits.Maximum_String_Bytes, "configuration");
         Check_String (Toolchain, Limits.Maximum_String_Bytes, "toolchain identity");
         Result.Model :=
           (Module_Name        => To_Unbounded_String (Module_Name),
            Configuration      => To_Unbounded_String (Configuration),
            Source_SHA256      => To_Unbounded_String (Source_SHA256),
            Toolchain_Identity => To_Unbounded_String (Toolchain));
         declare
            Initial_State : constant String :=
              Flyology_TLA.JSON.Canonical_Image
                (Source, Flyology_TLA.JSON.Member (Source, Initial_Node, "state"));
         begin
            Check_String (Initial_State, Limits.Maximum_Value_Bytes, "initial state");
            Result.Initial_State_JSON := To_Unbounded_String (Initial_State);
         end;
         if Step_Count > 0 then
            for Offset in 0 .. Step_Count - 1 loop
               declare
               Node : constant Flyology_TLA.JSON.Value :=
                 Flyology_TLA.JSON.Element (Source, Steps_Node, Offset);
               Expected : constant Flyology_TLA.JSON.Value :=
                 Flyology_TLA.JSON.Member (Source, Node, "expected");
               Index : constant Natural :=
                 Flyology_TLA.JSON.Natural_Data
                   (Source, Flyology_TLA.JSON.Member (Source, Node, "index"));
               Action : constant String :=
                 Flyology_TLA.JSON.String_Data
                   (Source, Flyology_TLA.JSON.Member (Source, Node, "action"));
               Model_Source : constant String :=
                 Flyology_TLA.JSON.String_Data
                   (Source, Flyology_TLA.JSON.Member (Source, Node, "model_source"));
               Role : constant String :=
                 (if Flyology_TLA.JSON.Has_Member (Source, Node, "role")
                  then Flyology_TLA.JSON.String_Data
                    (Source, Flyology_TLA.JSON.Member (Source, Node, "role"))
                  else Action);
               Input : constant String :=
                 Flyology_TLA.JSON.Canonical_Image
                   (Source, Flyology_TLA.JSON.Member (Source, Node, "input"));
               Outcome : constant String :=
                 Flyology_TLA.JSON.Canonical_Image
                   (Source, Flyology_TLA.JSON.Member (Source, Expected, "outcome"));
               State : constant String :=
                 Flyology_TLA.JSON.Canonical_Image
                   (Source, Flyology_TLA.JSON.Member (Source, Expected, "state"));
            begin
               if Flyology_TLA.JSON.Object_Length (Source, Node) /=
                 (if Flyology_TLA.JSON.Has_Member (Source, Node, "role") then 6 else 5)
                 or else Flyology_TLA.JSON.Object_Length (Source, Expected) /= 2
               then
                  raise Trace_Error with "trace step has unknown or missing members";
               elsif Index /= Offset + 1 then
                  raise Trace_Error with "trace indices are not contiguous from one";
               elsif not Is_Qualified_Action (Action)
                 or else not Is_Qualified_Action (Model_Source)
               then
                  raise Trace_Error with "trace action or model_source is not qualified";
               elsif Action'Length <= Module_Name'Length + 1
                 or else Action (Action'First .. Action'First + Module_Name'Length - 1) /= Module_Name
                 or else Action (Action'First + Module_Name'Length) /= '!'
               then
                  raise Trace_Error with "trace action is not qualified by the model module";
               end if;
               Check_String (Action, Limits.Maximum_String_Bytes, "step action");
               Check_String (Model_Source, Limits.Maximum_String_Bytes, "step model_source");
               Check_String (Role, Limits.Maximum_String_Bytes, "step role");
               Check_String (Input, Limits.Maximum_Value_Bytes, "step input");
               Check_String (Outcome, Limits.Maximum_Value_Bytes, "expected outcome");
               Check_String (State, Limits.Maximum_Value_Bytes, "expected state");
               Result.Steps.Append
                 (Trace_Step'
                    (Index                 => Positive (Index),
                   Action                => To_Unbounded_String (Action),
                   Role                  => To_Unbounded_String (Role),
                   Input_JSON            => To_Unbounded_String (Input),
                   Expected_Outcome_JSON => To_Unbounded_String (Outcome),
                   Expected_State_JSON   => To_Unbounded_String (State),
                   Model_Source          => To_Unbounded_String (Model_Source)));
               end;
            end loop;
         end if;
      end;
      return Result;
   exception
      when Error : Flyology_TLA.JSON.JSON_Error =>
         raise Trace_Error with Ada.Exceptions.Exception_Message (Error);
   end Load;

   procedure Write_Prefix
     (Item              : Trace;
      Last_Step_To_Keep : Natural;
      Path              : String)
   is
      Output : Ada.Text_IO.File_Type;
   begin
      if Last_Step_To_Keep > Natural (Item.Steps.Length) then
         raise Trace_Error with "prefix length exceeds trace step count";
      end if;
      Ada.Text_IO.Create (Output, Ada.Text_IO.Out_File, Path);
      Ada.Text_IO.Put
        (Output,
         "{""format"":""flyology.tla.trace/1"",""model"":{""module"":"
         & Flyology_TLA.JSON.Quote (To_String (Item.Model.Module_Name))
         & ",""configuration"":"
         & Flyology_TLA.JSON.Quote (To_String (Item.Model.Configuration))
         & ",""source_sha256"":"
         & Flyology_TLA.JSON.Quote (To_String (Item.Model.Source_SHA256))
         & ",""toolchain"":"
         & Flyology_TLA.JSON.Quote (To_String (Item.Model.Toolchain_Identity))
         & "},""initial"":{""state"":"
         & To_String (Item.Initial_State_JSON)
         & "},""steps"":[");
      if Last_Step_To_Keep > 0 then
         for Index in 1 .. Last_Step_To_Keep loop
            declare
               Step : Trace_Step renames Item.Steps (Index);
            begin
               if Index > 1 then
                  Ada.Text_IO.Put (Output, ',');
               end if;
               Ada.Text_IO.Put
                 (Output,
                  "{""index"":"
                  & Ada.Strings.Fixed.Trim (Natural'Image (Index), Ada.Strings.Both)
                  & ",""action"":"
                  & Flyology_TLA.JSON.Quote (To_String (Step.Action))
                  & ",""role"":"
                  & Flyology_TLA.JSON.Quote (To_String (Step.Role))
                  & ",""input"":"
                  & To_String (Step.Input_JSON)
                  & ",""expected"":{""outcome"":"
                  & To_String (Step.Expected_Outcome_JSON)
                  & ",""state"":"
                  & To_String (Step.Expected_State_JSON)
                  & "},""model_source"":"
                  & Flyology_TLA.JSON.Quote (To_String (Step.Model_Source))
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
   end Write_Prefix;

end Flyology_TLA.Traces;
