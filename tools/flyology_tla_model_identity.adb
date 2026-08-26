with Ada.Containers.Indefinite_Vectors;
with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings;
with Ada.Strings.Fixed;
with Flyology_TLA.Codecs;
with GNAT.OS_Lib;
with GNAT.SHA256;

package body Flyology_TLA_Model_Identity is

   use Ada.Strings.Unbounded;
   use type Ada.Directories.File_Kind;
   use type Ada.Directories.File_Size;
   use type GNAT.OS_Lib.File_Descriptor;
   use type GNAT.OS_Lib.String_Access;

   package String_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Positive, Element_Type => String);

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Identity_Error with Message;
      end if;
   end Require;

   function Read_File (Path : String) return String is
      use type Ada.Streams.Stream_Element_Offset;
      Size : Ada.Directories.File_Size;
      File : Ada.Streams.Stream_IO.File_Type;
   begin
      Size := Ada.Directories.Size (Path);
      Require (Size > 0, "identity input is empty: " & Path);
      Require
        (Size <= Ada.Directories.File_Size (Natural'Last),
         "identity input is too large: " & Path);
      declare
         Data : Ada.Streams.Stream_Element_Array
           (1 .. Ada.Streams.Stream_Element_Offset (Size));
         Last : Ada.Streams.Stream_Element_Offset;
         Text : String (1 .. Natural (Size));
      begin
         Ada.Streams.Stream_IO.Open (File, Ada.Streams.Stream_IO.In_File, Path);
         Ada.Streams.Stream_IO.Read (File, Data, Last);
         Ada.Streams.Stream_IO.Close (File);
         Require (Last = Data'Last, "short identity read from: " & Path);
         for Index in Data'Range loop
            Text (Natural (Index)) := Character'Val (Data (Index));
         end loop;
         return Text;
      end;
   exception
      when Ada.Directories.Name_Error | Ada.Directories.Use_Error =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         raise Identity_Error with "cannot read identity input: " & Path;
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         raise;
   end Read_File;

   function Natural_Image (Value : Natural) return String is
     (Ada.Strings.Fixed.Trim (Natural'Image (Value), Ada.Strings.Both));

   function Element_Text
     (Source : String;
      Tag    : String;
      From   : Positive;
      Before : Natural := Natural'Last) return String
   is
      Opening : constant String := "<" & Tag & ">";
      Closing : constant String := "</" & Tag & ">";
      First   : constant Natural := Ada.Strings.Fixed.Index (Source, Opening, From);
      Last    : Natural;
   begin
      Require (First > 0 and then First < Before, "SANY XML lacks " & Tag);
      Last := Ada.Strings.Fixed.Index (Source, Closing, First + Opening'Length);
      Require (Last > 0 and then Last <= Before, "SANY XML has unterminated " & Tag);
      return Source (First + Opening'Length .. Last - 1);
   end Element_Text;

   procedure Insert_Name
     (Names : in out String_Vectors.Vector; Name : String)
   is
   begin
      for Index in Names.First_Index .. Names.Last_Index loop
         if Names (Index) = Name then
            return;
         elsif Name < Names (Index) then
            Names.Insert (Index, Name);
            return;
         end if;
      end loop;
      Names.Append (Name);
   end Insert_Name;

   function Resolved_Module_Names (Semantic_XML : String) return String_Vectors.Vector is
      Opening : constant String := "<ModuleNode>";
      Closing : constant String := "</ModuleNode>";
      Cursor  : Positive := Semantic_XML'First;
      Names   : String_Vectors.Vector;
   begin
      loop
         declare
            First : constant Natural :=
              Ada.Strings.Fixed.Index (Semantic_XML, Opening, Cursor);
         begin
            exit when First = 0;
            declare
               Last : constant Natural :=
                 Ada.Strings.Fixed.Index
                   (Semantic_XML, Closing, First + Opening'Length);
            begin
               Require (Last > 0, "SANY XML has unterminated ModuleNode");
               Insert_Name
                 (Names,
                  Element_Text
                    (Semantic_XML, "uniquename", First + Opening'Length, Last));
               exit when Last + Closing'Length > Semantic_XML'Last;
               Cursor := Last + Closing'Length;
            end;
         end;
      end loop;
      Require (not Names.Is_Empty, "SANY XML resolved no modules");
      return Names;
   end Resolved_Module_Names;

   function From_Semantic_XML
     (Module_Path        : String;
      Configuration_Path : String;
      Semantic_XML       : String) return Identity
   is
      Root_Name : constant String :=
        Element_Text (Semantic_XML, "RootModule", Semantic_XML'First);
      Directory : constant String := Ada.Directories.Containing_Directory (Module_Path);
      Names     : constant String_Vectors.Vector := Resolved_Module_Names (Semantic_XML);
      Closure   : Unbounded_String :=
        To_Unbounded_String ("flyology.tla.model-closure/1" & ASCII.LF);
      Root_Found : Boolean := False;
   begin
      for Name of Names loop
         declare
            Path : constant String := Ada.Directories.Compose (Directory, Name, "tla");
         begin
            if Ada.Directories.Exists (Path)
              and then Ada.Directories.Kind (Path) = Ada.Directories.Ordinary_File
            then
               declare
                  Source : constant String := Read_File (Path);
               begin
                  Append (Closure, Natural_Image (Name'Length) & ":" & Name & ASCII.LF);
                  Append
                    (Closure,
                     Natural_Image (Source'Length) & ":" & Source & ASCII.LF);
                  Root_Found := Root_Found or else Name = Root_Name;
               end;
            end if;
         end;
      end loop;
      Require
        (Root_Found,
         "SANY root module is not a resolved local file beside " & Module_Path);
      declare
         Configuration_Source : constant String := Read_File (Configuration_Path);
      begin
         return
           (Module_Name          => To_Unbounded_String (Root_Name),
            Configuration        =>
              To_Unbounded_String (Ada.Directories.Simple_Name (Configuration_Path)),
            Source_SHA256        =>
              To_Unbounded_String (GNAT.SHA256.Digest (To_String (Closure))),
            Configuration_SHA256 =>
              To_Unbounded_String (GNAT.SHA256.Digest (Configuration_Source)),
            Semantic_XML_SHA256  =>
              To_Unbounded_String (GNAT.SHA256.Digest (Semantic_XML)));
      end;
   end From_Semantic_XML;

   function Export_Semantic_XML
     (Module_Path  : String;
      Java_Path    : String;
      TLC_Jar_Path : String) return String
   is
      Temporary_FD   : GNAT.OS_Lib.File_Descriptor := GNAT.OS_Lib.Invalid_FD;
      Temporary_Name : GNAT.OS_Lib.String_Access := null;
      Module_Full    : Unbounded_String;
      Directory      : Unbounded_String;
      Java_Full      : Unbounded_String;
      Jar_Full       : Unbounded_String;
      Original       : Unbounded_String;
      Directory_Changed : Boolean := False;
      Return_Code     : Integer;
   begin
      Require
        (Ada.Directories.Exists (Module_Path)
         and then Ada.Directories.Kind (Module_Path) = Ada.Directories.Ordinary_File,
         "TLA+ root module is not a file: " & Module_Path);
      Require
        (Ada.Directories.Exists (Java_Path)
         and then Ada.Directories.Kind (Java_Path) = Ada.Directories.Ordinary_File,
         "Java executable is not a file: " & Java_Path);
      Require
        (Ada.Directories.Exists (TLC_Jar_Path)
         and then Ada.Directories.Kind (TLC_Jar_Path) = Ada.Directories.Ordinary_File,
         "TLA+ Tools jar is not a file: " & TLC_Jar_Path);
      Module_Full := To_Unbounded_String (Ada.Directories.Full_Name (Module_Path));
      Directory := To_Unbounded_String
        (Ada.Directories.Containing_Directory (To_String (Module_Full)));
      Java_Full := To_Unbounded_String (Ada.Directories.Full_Name (Java_Path));
      Jar_Full := To_Unbounded_String (Ada.Directories.Full_Name (TLC_Jar_Path));
      Original := To_Unbounded_String (Ada.Directories.Current_Directory);
      GNAT.OS_Lib.Create_Temp_File (Temporary_FD, Temporary_Name);
      Require
        (Temporary_FD /= GNAT.OS_Lib.Invalid_FD,
         "cannot create temporary model identity XML file");
      declare
         Arguments : GNAT.OS_Lib.Argument_List (1 .. 8) :=
           [new String'("-cp"),
            new String'(To_String (Jar_Full)),
            new String'("tla2sany.xml.XMLExporter"),
            new String'("-o"),
            new String'("-r"),
            new String'("-I"),
            new String'(To_String (Directory)),
            new String'(To_String (Module_Full))];
      begin
         Ada.Directories.Set_Directory (To_String (Directory));
         Directory_Changed := True;
         begin
            GNAT.OS_Lib.Spawn
              (To_String (Java_Full),
               Arguments,
               Temporary_FD,
               Return_Code,
               Err_To_Out => True);
         exception
            when others =>
               for Argument of Arguments loop
                  GNAT.OS_Lib.Free (Argument);
               end loop;
               raise;
         end;
         Ada.Directories.Set_Directory (To_String (Original));
         Directory_Changed := False;
         GNAT.OS_Lib.Close (Temporary_FD);
         Temporary_FD := GNAT.OS_Lib.Invalid_FD;
         for Argument of Arguments loop
            GNAT.OS_Lib.Free (Argument);
         end loop;
      end;
      if Return_Code /= 0 then
         declare
            Diagnostic : constant String :=
              (if Ada.Directories.Size (Temporary_Name.all) = 0
               then "no diagnostic output"
               else Read_File (Temporary_Name.all));
            Last : constant Natural :=
              Natural'Min (Diagnostic'Last, Diagnostic'First + 4_095);
         begin
            raise Identity_Error with
              "SANY model identity export failed: "
              & Diagnostic (Diagnostic'First .. Last);
         end;
      end if;
      declare
         Result : constant String := Read_File (Temporary_Name.all);
      begin
         Ada.Directories.Delete_File (Temporary_Name.all);
         GNAT.OS_Lib.Free (Temporary_Name);
         return Result;
      end;
   exception
      when others =>
         if Directory_Changed then
            Ada.Directories.Set_Directory (To_String (Original));
         end if;
         if Temporary_FD /= GNAT.OS_Lib.Invalid_FD then
            GNAT.OS_Lib.Close (Temporary_FD);
         end if;
         if Temporary_Name /= null then
            if Ada.Directories.Exists (Temporary_Name.all) then
               Ada.Directories.Delete_File (Temporary_Name.all);
            end if;
            GNAT.OS_Lib.Free (Temporary_Name);
         end if;
         raise;
   end Export_Semantic_XML;

   function Resolve
     (Module_Path        : String;
      Configuration_Path : String;
      Java_Path          : String;
      TLC_Jar_Path       : String) return Identity is
     (From_Semantic_XML
        (Module_Path,
         Configuration_Path,
         Export_Semantic_XML (Module_Path, Java_Path, TLC_Jar_Path)));

   function JSON_Image (Item : Identity) return String is
     ("{""format"":""flyology.tla.model-identity/1"",""module"":"
      & Flyology_TLA.Codecs.Encode_String (To_String (Item.Module_Name))
      & ",""configuration"":"
      & Flyology_TLA.Codecs.Encode_String (To_String (Item.Configuration))
      & ",""source_sha256"":"
      & Flyology_TLA.Codecs.Encode_String (To_String (Item.Source_SHA256))
      & ",""configuration_sha256"":"
      & Flyology_TLA.Codecs.Encode_String (To_String (Item.Configuration_SHA256))
      & ",""semantic_xml_sha256"":"
      & Flyology_TLA.Codecs.Encode_String (To_String (Item.Semantic_XML_SHA256))
      & "}");

end Flyology_TLA_Model_Identity;
