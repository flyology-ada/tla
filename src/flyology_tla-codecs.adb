with Ada.Characters.Handling;
with Ada.Strings;
with Ada.Strings.Fixed;
with Flyology_TLA.JSON;

package body Flyology_TLA.Codecs is

   use type Flyology_TLA.JSON.Value_Kind;

   function Object_Member
     (Source : String;
      Name   : String;
      Limits : Flyology_TLA.Traces.Load_Limits) return String
   is
      Root : Flyology_TLA.JSON.Value;
   begin
      if Source'Length > Limits.Maximum_Value_Bytes then
         raise Codec_Error with "JSON value exceeds caller limit";
      end if;
      Flyology_TLA.JSON.Validate
        (Source,
         Limits.Maximum_JSON_Depth,
         Limits.Maximum_Name_Bytes,
         Limits.Maximum_Object_Names);
      Root := Flyology_TLA.JSON.Root (Source);
      return Flyology_TLA.JSON.Canonical_Image
        (Source, Flyology_TLA.JSON.Member (Source, Root, Name));
   exception
      when Flyology_TLA.JSON.JSON_Error =>
         raise Codec_Error with "cannot decode object member '" & Name & "'";
   end Object_Member;

   function Object_Size
     (Source : String;
      Limits : Flyology_TLA.Traces.Load_Limits) return Natural
   is
      Root : Flyology_TLA.JSON.Value;
   begin
      if Source'Length > Limits.Maximum_Value_Bytes then
         raise Codec_Error with "JSON value exceeds caller limit";
      end if;
      Flyology_TLA.JSON.Validate
        (Source,
         Limits.Maximum_JSON_Depth,
         Limits.Maximum_Name_Bytes,
         Limits.Maximum_Object_Names);
      Root := Flyology_TLA.JSON.Root (Source);
      return Flyology_TLA.JSON.Object_Length (Source, Root);
   exception
      when Flyology_TLA.JSON.JSON_Error =>
         raise Codec_Error with "expected a JSON object";
   end Object_Size;

   function Decode_Integer (Source : String) return Long_Long_Integer is
      Wrapped : constant String := "{""value"":" & Source & "}";
      Root    : Flyology_TLA.JSON.Value;
      Item    : Flyology_TLA.JSON.Value;
   begin
      Flyology_TLA.JSON.Validate (Wrapped, 4, 64, 2);
      Root := Flyology_TLA.JSON.Root (Wrapped);
      Item := Flyology_TLA.JSON.Member (Wrapped, Root, "value");
      if Flyology_TLA.JSON.Kind (Item) /= Flyology_TLA.JSON.Number_Value then
         raise Codec_Error with "expected a canonical JSON integer";
      end if;
      return Long_Long_Integer'Value (Flyology_TLA.JSON.Image (Wrapped, Item));
   exception
      when Constraint_Error =>
         raise Codec_Error with "JSON integer is outside the Ada harness range";
      when Flyology_TLA.JSON.JSON_Error =>
         raise Codec_Error with "expected a canonical JSON integer";
   end Decode_Integer;

   function Decode_Boolean (Source : String) return Boolean is
      Wrapped : constant String := "{""value"":" & Source & "}";
      Root    : Flyology_TLA.JSON.Value;
      Item    : Flyology_TLA.JSON.Value;
   begin
      Flyology_TLA.JSON.Validate (Wrapped, 4, 64, 2);
      Root := Flyology_TLA.JSON.Root (Wrapped);
      Item := Flyology_TLA.JSON.Member (Wrapped, Root, "value");
      if Flyology_TLA.JSON.Kind (Item) /= Flyology_TLA.JSON.Boolean_Value then
         raise Codec_Error with "expected a JSON boolean";
      elsif Flyology_TLA.JSON.Image (Wrapped, Item) = "true" then
         return True;
      else
         return False;
      end if;
   exception
      when Flyology_TLA.JSON.JSON_Error =>
         raise Codec_Error with "expected a JSON boolean";
   end Decode_Boolean;

   function Decode_String (Source : String) return String is
      Wrapped : constant String := "{""value"":" & Source & "}";
      Root    : Flyology_TLA.JSON.Value;
      Item    : Flyology_TLA.JSON.Value;
   begin
      Flyology_TLA.JSON.Validate (Wrapped, 4, 64, 2);
      Root := Flyology_TLA.JSON.Root (Wrapped);
      Item := Flyology_TLA.JSON.Member (Wrapped, Root, "value");
      if Flyology_TLA.JSON.Kind (Item) /= Flyology_TLA.JSON.String_Value then
         raise Codec_Error with "expected a JSON string";
      end if;
      return Flyology_TLA.JSON.String_Data (Wrapped, Item);
   exception
      when Flyology_TLA.JSON.JSON_Error =>
         raise Codec_Error with "expected a JSON string";
   end Decode_String;

   function Encode_Integer (Value : Long_Long_Integer) return String is
     (Ada.Strings.Fixed.Trim (Long_Long_Integer'Image (Value), Ada.Strings.Both));

   function Encode_Boolean (Value : Boolean) return String is
     (Ada.Characters.Handling.To_Lower (Boolean'Image (Value)));

   function Encode_String (Value : String) return String is
     (Flyology_TLA.JSON.Quote (Value));

end Flyology_TLA.Codecs;
