private package Flyology_TLA.JSON is

   type Value_Kind is
     (Null_Value, Boolean_Value, Number_Value, String_Value, Array_Value, Object_Value);

   type Value is private;

   function Read_File (Path : String; Maximum_Bytes : Positive) return String;

   procedure Validate
     (Source              : String;
      Maximum_Depth       : Positive;
      Maximum_Name_Octets : Positive;
      Maximum_Names       : Positive);

   function Root (Source : String) return Value;
   function Kind (Item : Value) return Value_Kind;
   function Image (Source : String; Item : Value) return String;
   function Canonical_Image (Source : String; Item : Value) return String;
   function Canonical_Value
     (Source               : String;
      Maximum_Depth        : Positive;
      Maximum_Name_Octets  : Positive;
      Maximum_Object_Names : Positive;
      Maximum_String_Bytes : Positive;
      Maximum_Value_Bytes  : Positive) return String;
   function String_Data (Source : String; Item : Value) return String;
   function Natural_Data (Source : String; Item : Value) return Natural;

   function Has_Member (Source : String; Item : Value; Name : String) return Boolean;
   function Member (Source : String; Item : Value; Name : String) return Value;
   function Length (Source : String; Item : Value) return Natural;
   function Object_Length (Source : String; Item : Value) return Natural;
   function Element (Source : String; Item : Value; Index : Natural) return Value;

   function Equivalent
     (Left_Source          : String;
      Right_Source         : String;
      Maximum_Depth        : Positive;
      Maximum_Name_Octets  : Positive;
      Maximum_Object_Names : Positive) return Boolean;

   function Quote (Value : String) return String;

   JSON_Error : exception;

private
   type Value is record
      Form       : Value_Kind := Null_Value;
      First      : Natural := 0;
      After_Last : Natural := 0;
   end record;

end Flyology_TLA.JSON;
