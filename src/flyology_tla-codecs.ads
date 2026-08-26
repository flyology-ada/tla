with Flyology_TLA.Traces;

package Flyology_TLA.Codecs is

   function Object_Member
     (Source : String;
      Name   : String;
      Limits : Flyology_TLA.Traces.Load_Limits) return String;

   function Object_Size
     (Source : String;
      Limits : Flyology_TLA.Traces.Load_Limits) return Natural;

   function Decode_Integer (Source : String) return Long_Long_Integer;
   function Decode_Boolean (Source : String) return Boolean;
   function Decode_String (Source : String) return String;

   function Encode_Integer (Value : Long_Long_Integer) return String;
   function Encode_Boolean (Value : Boolean) return String;
   function Encode_String (Value : String) return String;

   Codec_Error : exception;

end Flyology_TLA.Codecs;
