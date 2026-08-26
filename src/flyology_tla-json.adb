with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded;
with Flyology_JSON.Errors;
with Flyology_JSON.Parsing;
with Flyology_JSON.Profiles;

package body Flyology_TLA.JSON is

   use Ada.Strings.Unbounded;
   use type Ada.Streams.Stream_Element_Count;
   use type Ada.Directories.File_Size;
   use type Flyology_JSON.Errors.Error_Code;

   package Strict_Parsing is new
     Flyology_JSON.Parsing
       (Duplicate_Mode => Flyology_JSON.Profiles.Reject_Duplicates);

   use type Strict_Parsing.Step_Outcome;

   function Read_File (Path : String; Maximum_Bytes : Positive) return String is
      Size : constant Ada.Directories.File_Size := Ada.Directories.Size (Path);
   begin
      if Size = 0 then
         raise JSON_Error with "JSON document is empty";
      elsif Size > Ada.Directories.File_Size (Maximum_Bytes) then
         raise JSON_Error with "JSON document exceeds caller limit";
      end if;
      declare
         File : Ada.Streams.Stream_IO.File_Type;
         Data : Ada.Streams.Stream_Element_Array
           (1 .. Ada.Streams.Stream_Element_Offset (Size));
         Last : Ada.Streams.Stream_Element_Offset;
         Text : String (1 .. Natural (Size));
      begin
         Ada.Streams.Stream_IO.Open
           (File, Ada.Streams.Stream_IO.In_File, Path);
         Ada.Streams.Stream_IO.Read (File, Data, Last);
         Ada.Streams.Stream_IO.Close (File);
         if Last /= Data'Last then
            raise JSON_Error with "short read while loading JSON document";
         end if;
         for Index in Data'Range loop
            Text (Natural (Index)) := Character'Val (Data (Index));
         end loop;
         return Text;
      exception
         when others =>
            if Ada.Streams.Stream_IO.Is_Open (File) then
               Ada.Streams.Stream_IO.Close (File);
            end if;
            raise;
      end;
   exception
      when Ada.Directories.Name_Error | Ada.Directories.Use_Error =>
         raise JSON_Error with "cannot read JSON document: " & Path;
   end Read_File;

   procedure Validate
     (Source              : String;
      Maximum_Depth       : Positive;
      Maximum_Name_Octets : Positive;
      Maximum_Names       : Positive)
   is
      Profile : constant Flyology_JSON.Profiles.Parser_Profile :=
        (Syntax        =>
           (Family  => Flyology_JSON.Profiles.RFC_8259,
            Version => 1),
         Unicode       =>
           (Family  => Flyology_JSON.Profiles.Unicode_Scalars,
            Version => 1),
         Compatibility =>
           (Family  => Flyology_JSON.Profiles.No_Extensions,
            Version => 1),
         BOM           => Flyology_JSON.Profiles.Reject_BOM,
         Duplicates    => Flyology_JSON.Profiles.Reject_Duplicates,
         Top_Level     => Flyology_JSON.Profiles.Require_Object);
      Parser  : Strict_Parsing.Parser
        (Maximum_Depth,
         Maximum_Name_Octets,
         Maximum_Names);
      Report  : Flyology_JSON.Errors.Diagnostic;
      Data    : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Source'Length));
      Cursor  : Ada.Streams.Stream_Element_Offset := Data'First;
   begin
      for Offset in Source'Range loop
         Data
           (Ada.Streams.Stream_Element_Offset
              (Offset - Source'First + 1)) :=
            Ada.Streams.Stream_Element (Character'Pos (Source (Offset)));
      end loop;
      Strict_Parsing.Initialize (Parser, Profile, Report);
      if Report.Code /= Flyology_JSON.Errors.No_Error then
         raise JSON_Error with "flyology_json rejected parser profile";
      end if;
      loop
         declare
            Step : Strict_Parsing.Step_Result;
         begin
            Strict_Parsing.Step
              (Parser,
               Data (Cursor .. Data'Last),
               End_Of_Input => True,
               Result       => Step);
            Cursor := Cursor + Ada.Streams.Stream_Element_Offset (Step.Consumed);
            case Step.Outcome is
               when Strict_Parsing.Event_Ready =>
                  null;
               when Strict_Parsing.Document_Complete =>
                  return;
               when Strict_Parsing.Need_Input =>
                  raise JSON_Error with "flyology_json requested input after final chunk";
               when Strict_Parsing.Step_Failed | Strict_Parsing.Call_Rejected =>
                  raise JSON_Error
                    with "flyology_json rejected document: "
                    & Flyology_JSON.Errors.Error_Code'Image (Step.Diagnostic.Code)
                    & " at byte"
                    & Flyology_JSON.Errors.Byte_Offset'Image
                        (Step.Diagnostic.Offset);
            end case;
         end;
      end loop;
   end Validate;

   function Skip_Whitespace (Source : String; Position : Natural) return Natural is
      Cursor : Natural := Position;
   begin
      while Cursor <= Source'Last
        and then Source (Cursor) in ' ' | ASCII.HT | ASCII.LF | ASCII.CR
      loop
         Cursor := Cursor + 1;
      end loop;
      return Cursor;
   end Skip_Whitespace;

   function String_End (Source : String; Position : Natural) return Natural is
      Cursor : Natural := Position + 1;
   begin
      while Cursor <= Source'Last loop
         if Source (Cursor) = '"' then
            return Cursor + 1;
         elsif Source (Cursor) = '\' then
            Cursor := Cursor + 2;
         else
            Cursor := Cursor + 1;
         end if;
      end loop;
      raise JSON_Error with "unterminated JSON string after validation";
   end String_End;

   function Scan (Source : String; Position : Natural) return Value;

   function Scan (Source : String; Position : Natural) return Value is
      Start  : constant Natural := Skip_Whitespace (Source, Position);
      Cursor : Natural := Start;
   begin
      if Start > Source'Last then
         raise JSON_Error with "missing JSON value";
      end if;
      case Source (Start) is
         when 'n' =>
            return (Null_Value, Start, Start + 4);
         when 't' =>
            return (Boolean_Value, Start, Start + 4);
         when 'f' =>
            return (Boolean_Value, Start, Start + 5);
         when '"' =>
            return (String_Value, Start, String_End (Source, Start));
         when '[' =>
            Cursor := Skip_Whitespace (Source, Start + 1);
            if Source (Cursor) = ']' then
               return (Array_Value, Start, Cursor + 1);
            end if;
            loop
               Cursor := Scan (Source, Cursor).After_Last;
               Cursor := Skip_Whitespace (Source, Cursor);
               exit when Source (Cursor) = ']';
               Cursor := Skip_Whitespace (Source, Cursor + 1);
            end loop;
            return (Array_Value, Start, Cursor + 1);
         when '{' =>
            Cursor := Skip_Whitespace (Source, Start + 1);
            if Source (Cursor) = '}' then
               return (Object_Value, Start, Cursor + 1);
            end if;
            loop
               Cursor := String_End (Source, Cursor);
               Cursor := Skip_Whitespace (Source, Cursor);
               Cursor := Skip_Whitespace (Source, Cursor + 1);
               Cursor := Scan (Source, Cursor).After_Last;
               Cursor := Skip_Whitespace (Source, Cursor);
               exit when Source (Cursor) = '}';
               Cursor := Skip_Whitespace (Source, Cursor + 1);
            end loop;
            return (Object_Value, Start, Cursor + 1);
         when others =>
            while Cursor <= Source'Last
              and then Source (Cursor) not in ' ' | ASCII.HT | ASCII.LF | ASCII.CR | ',' | ']' | '}'
            loop
               Cursor := Cursor + 1;
            end loop;
            return (Number_Value, Start, Cursor);
      end case;
   end Scan;

   function Root (Source : String) return Value is
      Result : constant Value := Scan (Source, Source'First);
   begin
      if Result.Form /= Object_Value then
         raise JSON_Error with "JSON root is not an object";
      end if;
      return Result;
   end Root;

   function Kind (Item : Value) return Value_Kind is (Item.Form);

   function Image (Source : String; Item : Value) return String is
     (Source (Item.First .. Item.After_Last - 1));

   function Hex_Value (Item : Character) return Natural is
     (case Item is
         when '0' .. '9' => Character'Pos (Item) - Character'Pos ('0'),
         when 'a' .. 'f' => Character'Pos (Item) - Character'Pos ('a') + 10,
         when 'A' .. 'F' => Character'Pos (Item) - Character'Pos ('A') + 10,
         when others     => raise JSON_Error with "invalid hexadecimal escape");

   procedure Append_UTF8 (Target : in out Unbounded_String; Scalar : Natural) is
   begin
      if Scalar <= 16#7F# then
         Append (Target, Character'Val (Scalar));
      elsif Scalar <= 16#7FF# then
         Append (Target, Character'Val (16#C0# + Scalar / 64));
         Append (Target, Character'Val (16#80# + Scalar mod 64));
      elsif Scalar <= 16#FFFF# then
         Append (Target, Character'Val (16#E0# + Scalar / 4_096));
         Append (Target, Character'Val (16#80# + (Scalar / 64) mod 64));
         Append (Target, Character'Val (16#80# + Scalar mod 64));
      else
         Append (Target, Character'Val (16#F0# + Scalar / 262_144));
         Append (Target, Character'Val (16#80# + (Scalar / 4_096) mod 64));
         Append (Target, Character'Val (16#80# + (Scalar / 64) mod 64));
         Append (Target, Character'Val (16#80# + Scalar mod 64));
      end if;
   end Append_UTF8;

   function String_Data (Source : String; Item : Value) return String is
      Result : Unbounded_String;
      Cursor : Natural := Item.First + 1;
      Limit  : constant Natural := Item.After_Last - 1;
   begin
      if Item.Form /= String_Value then
         raise JSON_Error with "JSON value is not a string";
      end if;
      while Cursor < Limit loop
         if Source (Cursor) /= '\' then
            Append (Result, Source (Cursor));
            Cursor := Cursor + 1;
         else
            case Source (Cursor + 1) is
               when '"' => Append (Result, '"'); Cursor := Cursor + 2;
               when '\' => Append (Result, '\'); Cursor := Cursor + 2;
               when '/' => Append (Result, '/'); Cursor := Cursor + 2;
               when 'b' => Append (Result, ASCII.BS); Cursor := Cursor + 2;
               when 'f' => Append (Result, ASCII.FF); Cursor := Cursor + 2;
               when 'n' => Append (Result, ASCII.LF); Cursor := Cursor + 2;
               when 'r' => Append (Result, ASCII.CR); Cursor := Cursor + 2;
               when 't' => Append (Result, ASCII.HT); Cursor := Cursor + 2;
               when 'u' =>
                  declare
                     Scalar : Natural := 0;
                  begin
                     for Offset in 2 .. 5 loop
                        Scalar := Scalar * 16 + Hex_Value (Source (Cursor + Offset));
                     end loop;
                     Cursor := Cursor + 6;
                     if Scalar in 16#D800# .. 16#DBFF# then
                        declare
                           Low : Natural := 0;
                        begin
                           for Offset in 2 .. 5 loop
                              Low := Low * 16 + Hex_Value (Source (Cursor + Offset));
                           end loop;
                           Scalar := 16#10000# + (Scalar - 16#D800#) * 1_024 + Low - 16#DC00#;
                           Cursor := Cursor + 6;
                        end;
                     end if;
                     Append_UTF8 (Result, Scalar);
                  end;
               when others =>
                  raise JSON_Error with "invalid string escape after validation";
            end case;
         end if;
      end loop;
      return To_String (Result);
   end String_Data;

   function Natural_Data (Source : String; Item : Value) return Natural is
      Result : Natural := 0;
   begin
      if Item.Form /= Number_Value then
         raise JSON_Error with "JSON value is not a number";
      end if;
      for Cursor in Item.First .. Item.After_Last - 1 loop
         if Source (Cursor) not in '0' .. '9'
           or else Result > (Natural'Last - (Character'Pos (Source (Cursor)) - Character'Pos ('0'))) / 10
         then
            raise JSON_Error with "JSON number is not a representable natural";
         end if;
         Result := Result * 10 + Character'Pos (Source (Cursor)) - Character'Pos ('0');
      end loop;
      return Result;
   end Natural_Data;

   procedure Find_Member
     (Source : String;
      Item   : Value;
      Name   : String;
      Found  : out Boolean;
      Result : out Value)
   is
      Cursor : Natural;
   begin
      if Item.Form /= Object_Value then
         raise JSON_Error with "JSON value is not an object";
      end if;
      Cursor := Skip_Whitespace (Source, Item.First + 1);
      while Source (Cursor) /= '}' loop
         declare
            Name_Node : constant Value :=
              (String_Value, Cursor, String_End (Source, Cursor));
            Value_Start : Natural;
            Value_Node  : Value;
         begin
            Cursor := Skip_Whitespace (Source, Name_Node.After_Last);
            Value_Start := Skip_Whitespace (Source, Cursor + 1);
            Value_Node := Scan (Source, Value_Start);
            if String_Data (Source, Name_Node) = Name then
               Found := True;
               Result := Value_Node;
               return;
            end if;
            Cursor := Skip_Whitespace (Source, Value_Node.After_Last);
            if Source (Cursor) = ',' then
               Cursor := Skip_Whitespace (Source, Cursor + 1);
            end if;
         end;
      end loop;
      Found := False;
      Result := (others => <>);
   end Find_Member;

   function Has_Member (Source : String; Item : Value; Name : String) return Boolean is
      Found  : Boolean;
      Result : Value;
   begin
      Find_Member (Source, Item, Name, Found, Result);
      return Found;
   end Has_Member;

   function Member (Source : String; Item : Value; Name : String) return Value is
      Found  : Boolean;
      Result : Value;
   begin
      Find_Member (Source, Item, Name, Found, Result);
      if not Found then
         raise JSON_Error with "missing JSON member: " & Name;
      end if;
      return Result;
   end Member;

   function Length (Source : String; Item : Value) return Natural is
      Cursor : Natural;
      Count  : Natural := 0;
   begin
      if Item.Form /= Array_Value then
         raise JSON_Error with "JSON value is not an array";
      end if;
      Cursor := Skip_Whitespace (Source, Item.First + 1);
      while Source (Cursor) /= ']' loop
         Count := Count + 1;
         Cursor := Skip_Whitespace (Source, Scan (Source, Cursor).After_Last);
         if Source (Cursor) = ',' then
            Cursor := Skip_Whitespace (Source, Cursor + 1);
         end if;
      end loop;
      return Count;
   end Length;

   function Object_Length (Source : String; Item : Value) return Natural is
      Cursor : Natural;
      Count  : Natural := 0;
   begin
      if Item.Form /= Object_Value then
         raise JSON_Error with "JSON value is not an object";
      end if;
      Cursor := Skip_Whitespace (Source, Item.First + 1);
      while Source (Cursor) /= '}' loop
         Cursor := String_End (Source, Cursor);
         Cursor := Skip_Whitespace (Source, Cursor);
         Cursor := Skip_Whitespace (Source, Cursor + 1);
         Cursor := Skip_Whitespace (Source, Scan (Source, Cursor).After_Last);
         Count := Count + 1;
         if Source (Cursor) = ',' then
            Cursor := Skip_Whitespace (Source, Cursor + 1);
         end if;
      end loop;
      return Count;
   end Object_Length;

   function Element (Source : String; Item : Value; Index : Natural) return Value is
      Cursor  : Natural;
      Current : Natural := 0;
   begin
      if Item.Form /= Array_Value then
         raise JSON_Error with "JSON value is not an array";
      end if;
      Cursor := Skip_Whitespace (Source, Item.First + 1);
      while Source (Cursor) /= ']' loop
         declare
            Candidate : constant Value := Scan (Source, Cursor);
         begin
            if Current = Index then
               return Candidate;
            end if;
            Current := Current + 1;
            Cursor := Skip_Whitespace (Source, Candidate.After_Last);
            if Source (Cursor) = ',' then
               Cursor := Skip_Whitespace (Source, Cursor + 1);
            end if;
         end;
      end loop;
      raise JSON_Error with "JSON array index is out of range";
   end Element;

   function Quote (Value : String) return String is
      Result : Unbounded_String := To_Unbounded_String ("""");
      Hex    : constant String := "0123456789abcdef";
   begin
      for Item of Value loop
         case Item is
            when '"' => Append (Result, '\'); Append (Result, '"');
            when '\' => Append (Result, '\'); Append (Result, '\');
            when ASCII.BS => Append (Result, "\b");
            when ASCII.FF => Append (Result, "\f");
            when ASCII.LF => Append (Result, "\n");
            when ASCII.CR => Append (Result, "\r");
            when ASCII.HT => Append (Result, "\t");
            when others =>
               if Character'Pos (Item) <= 31 then
                  Append (Result, "\u00");
                  Append (Result, Hex (Character'Pos (Item) / 16 + 1));
                  Append (Result, Hex (Character'Pos (Item) mod 16 + 1));
               else
                  Append (Result, Item);
               end if;
         end case;
      end loop;
      Append (Result, '"');
      return To_String (Result);
   end Quote;

   function Canonical_Image (Source : String; Item : Value) return String is
      Result : Unbounded_String;
      Cursor : Natural;
   begin
      case Item.Form is
         when Null_Value | Boolean_Value | Number_Value =>
            return Image (Source, Item);
         when String_Value =>
            return Quote (String_Data (Source, Item));
         when Array_Value =>
            Append (Result, '[');
            declare
               Item_Count : constant Natural := Length (Source, Item);
            begin
               if Item_Count > 0 then
                  for Index in 0 .. Item_Count - 1 loop
                     if Index > 0 then
                        Append (Result, ',');
                     end if;
                     Append (Result, Canonical_Image (Source, Element (Source, Item, Index)));
                  end loop;
               end if;
            end;
            Append (Result, ']');
         when Object_Value =>
            Append (Result, '{');
            Cursor := Skip_Whitespace (Source, Item.First + 1);
            declare
               First_Member : Boolean := True;
            begin
               while Source (Cursor) /= '}' loop
                  declare
                     Name_Node : constant Value :=
                       (String_Value, Cursor, String_End (Source, Cursor));
                     Value_Start : Natural;
                     Value_Node  : Value;
                  begin
                     Cursor := Skip_Whitespace (Source, Name_Node.After_Last);
                     Value_Start := Skip_Whitespace (Source, Cursor + 1);
                     Value_Node := Scan (Source, Value_Start);
                     if not First_Member then
                        Append (Result, ',');
                     end if;
                     First_Member := False;
                     Append (Result, Quote (String_Data (Source, Name_Node)));
                     Append (Result, ':');
                     Append (Result, Canonical_Image (Source, Value_Node));
                     Cursor := Skip_Whitespace (Source, Value_Node.After_Last);
                     if Source (Cursor) = ',' then
                        Cursor := Skip_Whitespace (Source, Cursor + 1);
                     end if;
                  end;
               end loop;
            end;
            Append (Result, '}');
      end case;
      return To_String (Result);
   end Canonical_Image;

   function Equivalent_Node
     (Left_Source  : String;
      Left         : Value;
      Right_Source : String;
      Right        : Value) return Boolean
   is
   begin
      if Left.Form /= Right.Form then
         return False;
      end if;
      case Left.Form is
         when Null_Value | Boolean_Value | Number_Value =>
            return Image (Left_Source, Left) = Image (Right_Source, Right);
         when String_Value =>
            return String_Data (Left_Source, Left) = String_Data (Right_Source, Right);
         when Array_Value =>
            if Length (Left_Source, Left) /= Length (Right_Source, Right) then
               return False;
            end if;
            declare
               Item_Count : constant Natural := Length (Left_Source, Left);
            begin
               if Item_Count > 0 then
                  for Index in 0 .. Item_Count - 1 loop
                     if not Equivalent_Node
                       (Left_Source,
                        Element (Left_Source, Left, Index),
                        Right_Source,
                        Element (Right_Source, Right, Index))
                     then
                        return False;
                     end if;
                  end loop;
               end if;
            end;
            return True;
         when Object_Value =>
            if Object_Length (Left_Source, Left) /= Object_Length (Right_Source, Right) then
               return False;
            end if;
            declare
               Cursor : Natural := Skip_Whitespace (Left_Source, Left.First + 1);
            begin
               while Left_Source (Cursor) /= '}' loop
                  declare
                     Name_Node : constant Value :=
                       (String_Value, Cursor, String_End (Left_Source, Cursor));
                     Name        : constant String := String_Data (Left_Source, Name_Node);
                     Left_Start  : Natural;
                     Left_Value  : Value;
                     Right_Value : Value;
                     Found       : Boolean;
                  begin
                     Cursor := Skip_Whitespace (Left_Source, Name_Node.After_Last);
                     Left_Start := Skip_Whitespace (Left_Source, Cursor + 1);
                     Left_Value := Scan (Left_Source, Left_Start);
                     Find_Member (Right_Source, Right, Name, Found, Right_Value);
                     if not Found
                       or else not Equivalent_Node
                         (Left_Source, Left_Value, Right_Source, Right_Value)
                     then
                        return False;
                     end if;
                     Cursor := Skip_Whitespace (Left_Source, Left_Value.After_Last);
                     if Left_Source (Cursor) = ',' then
                        Cursor := Skip_Whitespace (Left_Source, Cursor + 1);
                     end if;
                  end;
               end loop;
            end;
            return True;
      end case;
   end Equivalent_Node;

   function Equivalent
     (Left_Source          : String;
      Right_Source         : String;
      Maximum_Depth        : Positive;
      Maximum_Name_Octets  : Positive;
      Maximum_Object_Names : Positive) return Boolean
   is
      Left_Document  : constant String := "{""value"":" & Left_Source & "}";
      Right_Document : constant String := "{""value"":" & Right_Source & "}";
      Comparison_Depth : constant Positive :=
        (if Maximum_Depth = Positive'Last then Maximum_Depth else Maximum_Depth + 1);
      Comparison_Names : constant Positive :=
        (if Maximum_Object_Names = Positive'Last
         then Maximum_Object_Names
         else Maximum_Object_Names + 1);
      Left_Root      : Value;
      Right_Root     : Value;
   begin
      Validate
        (Left_Document, Comparison_Depth, Maximum_Name_Octets, Comparison_Names);
      Validate
        (Right_Document, Comparison_Depth, Maximum_Name_Octets, Comparison_Names);
      Left_Root := Root (Left_Document);
      Right_Root := Root (Right_Document);
      return Equivalent_Node
        (Left_Document,
         Member (Left_Document, Left_Root, "value"),
         Right_Document,
         Member (Right_Document, Right_Root, "value"));
   end Equivalent;

end Flyology_TLA.JSON;
