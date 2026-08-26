with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;

package Flyology_TLA.Traces is

   type Load_Limits is record
      Maximum_File_Bytes   : Positive;
      Maximum_Steps        : Positive;
      Maximum_JSON_Depth   : Positive;
      Maximum_Object_Names : Positive;
      Maximum_Name_Bytes   : Positive;
      Maximum_String_Bytes : Positive;
      Maximum_Value_Bytes  : Positive;
   end record;

   type Model_Identity is record
      Module_Name       : Ada.Strings.Unbounded.Unbounded_String;
      Configuration     : Ada.Strings.Unbounded.Unbounded_String;
      Source_SHA256     : Ada.Strings.Unbounded.Unbounded_String;
      Toolchain_Identity : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   type Trace_Step is record
      Index                 : Positive;
      Action                : Ada.Strings.Unbounded.Unbounded_String;
      Role                  : Ada.Strings.Unbounded.Unbounded_String;
      Input_JSON            : Ada.Strings.Unbounded.Unbounded_String;
      Expected_Outcome_JSON : Ada.Strings.Unbounded.Unbounded_String;
      Expected_State_JSON   : Ada.Strings.Unbounded.Unbounded_String;
      Model_Source          : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   package Step_Vectors is new
     Ada.Containers.Vectors
       (Index_Type   => Positive,
        Element_Type => Trace_Step);

   type Trace is record
      Model              : Model_Identity;
      Initial_State_JSON : Ada.Strings.Unbounded.Unbounded_String;
      Steps              : Step_Vectors.Vector;
   end record;

   function Load (Path : String; Limits : Load_Limits) return Trace;

   function Load
     (Path   : String;
      Limits : Load_Limits;
      SHA256 : out Ada.Strings.Unbounded.Unbounded_String) return Trace;
   --  SHA256 is computed from the same byte string accepted by the parser.

   procedure Write_Prefix
     (Item              : Trace;
      Last_Step_To_Keep : Natural;
      Path              : String);

   Trace_Error : exception;

end Flyology_TLA.Traces;
