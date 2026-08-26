with Ada.Strings.Unbounded;

package Flyology_TLA_Model_Identity is

   type Identity is record
      Module_Name          : Ada.Strings.Unbounded.Unbounded_String;
      Configuration        : Ada.Strings.Unbounded.Unbounded_String;
      Source_SHA256        : Ada.Strings.Unbounded.Unbounded_String;
      Configuration_SHA256 : Ada.Strings.Unbounded.Unbounded_String;
      Semantic_XML_SHA256  : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   function Resolve
     (Module_Path        : String;
      Configuration_Path : String;
      Java_Path          : String;
      TLC_Jar_Path       : String) return Identity;

   function Export_Semantic_XML
     (Module_Path  : String;
      Java_Path    : String;
      TLC_Jar_Path : String) return String;
   --  Resolve with SANY from the root module directory, excluding the caller's
   --  working directory from the consumer-owned local module search boundary.

   function From_Semantic_XML
     (Module_Path        : String;
      Configuration_Path : String;
      Semantic_XML       : String) return Identity;

   function JSON_Image (Item : Identity) return String;

   Identity_Error : exception;

end Flyology_TLA_Model_Identity;
