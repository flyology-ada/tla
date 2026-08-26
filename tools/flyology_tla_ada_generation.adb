with Ada.Characters.Handling;
with Ada.Containers.Vectors;
with Ada.Directories;
with Ada.Strings;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology_TLA.Codecs;
with Flyology_TLA_Model_Identity;

package body Flyology_TLA_Ada_Generation is

   use Ada.Strings.Unbounded;
   use type Ada.Containers.Count_Type;
   use type Ada.Directories.File_Kind;

   Generation_Error : exception;

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Generation_Error with Message;
      end if;
   end Require;

   type XML_Node;
   type XML_Node_Access is access XML_Node;

   package XML_Node_Vectors is new Ada.Containers.Vectors
     (Index_Type => Natural, Element_Type => XML_Node_Access);

   type XML_Node is record
      Tag      : Unbounded_String;
      Text     : Unbounded_String;
      Children : XML_Node_Vectors.Vector;
   end record;

   function Decode_XML_Text (Value : String) return String is
      Result : Unbounded_String;
      Cursor : Natural := Value'First;
   begin
      while Cursor <= Value'Last loop
         if Value (Cursor) /= '&' then
            Append (Result, Value (Cursor));
            Cursor := Cursor + 1;
         elsif Cursor + 3 <= Value'Last
           and then Value (Cursor .. Cursor + 3) = "&lt;"
         then
            Append (Result, '<');
            Cursor := Cursor + 4;
         elsif Cursor + 3 <= Value'Last
           and then Value (Cursor .. Cursor + 3) = "&gt;"
         then
            Append (Result, '>');
            Cursor := Cursor + 4;
         elsif Cursor + 4 <= Value'Last
           and then Value (Cursor .. Cursor + 4) = "&amp;"
         then
            Append (Result, '&');
            Cursor := Cursor + 5;
         elsif Cursor + 5 <= Value'Last
           and then Value (Cursor .. Cursor + 5) = "&quot;"
         then
            Append (Result, '"');
            Cursor := Cursor + 6;
         elsif Cursor + 5 <= Value'Last
           and then Value (Cursor .. Cursor + 5) = "&apos;"
         then
            Append (Result, ''');
            Cursor := Cursor + 6;
         else
            raise Generation_Error with "unsupported XML entity in SANY output";
         end if;
      end loop;
      return To_String (Result);
   end Decode_XML_Text;

   procedure Skip_Whitespace (Source : String; Cursor : in out Natural) is
   begin
      while Cursor <= Source'Last
        and then Source (Cursor) in ' ' | ASCII.HT | ASCII.LF | ASCII.CR
      loop
         Cursor := Cursor + 1;
      end loop;
   end Skip_Whitespace;

   procedure Skip_Through
     (Source : String; Cursor : in out Natural; Terminator : String)
   is
   begin
      while Cursor + Terminator'Length - 1 <= Source'Last loop
         if Source (Cursor .. Cursor + Terminator'Length - 1) = Terminator then
            Cursor := Cursor + Terminator'Length;
            return;
         end if;
         Cursor := Cursor + 1;
      end loop;
      raise Generation_Error with "unterminated XML declaration or comment";
   end Skip_Through;

   procedure Skip_XML_Misc (Source : String; Cursor : in out Natural) is
   begin
      loop
         Skip_Whitespace (Source, Cursor);
         if Cursor + 1 <= Source'Last
           and then Source (Cursor .. Cursor + 1) = "<?"
         then
            Skip_Through (Source, Cursor, "?>");
         elsif Cursor + 3 <= Source'Last
           and then Source (Cursor .. Cursor + 3) = "<!--"
         then
            Skip_Through (Source, Cursor, "-->");
         else
            return;
         end if;
      end loop;
   end Skip_XML_Misc;

   function Parse_XML_Element
     (Source : String; Cursor : in out Natural) return XML_Node_Access;

   function Parse_XML_Element
     (Source : String; Cursor : in out Natural) return XML_Node_Access
   is
      Result    : constant XML_Node_Access := new XML_Node;
      Name_From : Natural;
      Name_To   : Natural;
      Quote     : Character := ASCII.NUL;
   begin
      Skip_XML_Misc (Source, Cursor);
      Require
        (Cursor <= Source'Last and then Source (Cursor) = '<',
         "expected XML element in SANY output");
      Cursor := Cursor + 1;
      Require
        (Cursor <= Source'Last and then Source (Cursor) /= '/',
         "unexpected XML closing element");
      Name_From := Cursor;
      while Cursor <= Source'Last
        and then Source (Cursor) not in ' ' | ASCII.HT | ASCII.LF | ASCII.CR | '>' | '/'
      loop
         Cursor := Cursor + 1;
      end loop;
      Name_To := Cursor - 1;
      Require (Name_To >= Name_From, "empty XML element name");
      Result.Tag := To_Unbounded_String (Source (Name_From .. Name_To));
      while Cursor <= Source'Last loop
         if Quote /= ASCII.NUL then
            if Source (Cursor) = Quote then
               Quote := ASCII.NUL;
            end if;
         elsif Source (Cursor) in ''' | '"' then
            Quote := Source (Cursor);
         elsif Source (Cursor) = '>' then
            Cursor := Cursor + 1;
            exit;
         elsif Source (Cursor) = '/'
           and then Cursor + 1 <= Source'Last
           and then Source (Cursor + 1) = '>'
         then
            Cursor := Cursor + 2;
            return Result;
         end if;
         Cursor := Cursor + 1;
      end loop;
      loop
         Require (Cursor <= Source'Last, "unterminated XML element " & To_String (Result.Tag));
         if Source (Cursor) = '<'
           and then Cursor + 1 <= Source'Last
           and then Source (Cursor + 1) = '/'
         then
            Cursor := Cursor + 2;
            Name_From := Cursor;
            while Cursor <= Source'Last and then Source (Cursor) /= '>' loop
               Cursor := Cursor + 1;
            end loop;
            Require (Cursor <= Source'Last, "unterminated XML closing element");
            Require
              (Source (Name_From .. Cursor - 1) = To_String (Result.Tag),
               "mismatched XML closing element for " & To_String (Result.Tag));
            Cursor := Cursor + 1;
            return Result;
         elsif Cursor + 8 <= Source'Last
           and then Source (Cursor .. Cursor + 8) = "<![CDATA["
         then
            Cursor := Cursor + 9;
            Name_From := Cursor;
            while Cursor + 2 <= Source'Last
              and then Source (Cursor .. Cursor + 2) /= "]]>"
            loop
               Cursor := Cursor + 1;
            end loop;
            Require
              (Cursor + 2 <= Source'Last,
               "unterminated CDATA section in SANY XML");
            Append (Result.Text, Source (Name_From .. Cursor - 1));
            Cursor := Cursor + 3;
         elsif Source (Cursor) = '<' then
            Result.Children.Append (Parse_XML_Element (Source, Cursor));
         else
            Name_From := Cursor;
            while Cursor <= Source'Last and then Source (Cursor) /= '<' loop
               Cursor := Cursor + 1;
            end loop;
            Append
              (Result.Text,
               Decode_XML_Text (Source (Name_From .. Cursor - 1)));
         end if;
      end loop;
   end Parse_XML_Element;

   function Parse_XML (Source : String) return XML_Node_Access is
      Cursor : Natural := Source'First;
      Result : XML_Node_Access;
   begin
      Result := Parse_XML_Element (Source, Cursor);
      Skip_XML_Misc (Source, Cursor);
      Require (Cursor > Source'Last, "trailing data after SANY XML document");
      return Result;
   end Parse_XML;

   function Child
     (Parent : XML_Node_Access; Tag : String; Required : Boolean := True)
      return XML_Node_Access
   is
   begin
      for Item of Parent.Children loop
         if To_String (Item.Tag) = Tag then
            return Item;
         end if;
      end loop;
      if Required then
         raise Generation_Error
           with "SANY XML node " & To_String (Parent.Tag) & " lacks " & Tag;
      end if;
      return null;
   end Child;

   function First_Child (Parent : XML_Node_Access) return XML_Node_Access is
   begin
      Require (not Parent.Children.Is_Empty, "empty SANY XML wrapper " & To_String (Parent.Tag));
      return Parent.Children.First_Element;
   end First_Child;

   function Node_Text (Node : XML_Node_Access) return String is
     (Ada.Strings.Fixed.Trim (To_String (Node.Text), Ada.Strings.Both));

   function Child_Text
     (Parent : XML_Node_Access; Tag : String; Required : Boolean := True) return String
   is
      Item : constant XML_Node_Access := Child (Parent, Tag, Required);
   begin
      return (if Item = null then "" else Node_Text (Item));
   end Child_Text;

   type Context_Entry is record
      UID  : Natural;
      Node : XML_Node_Access;
   end record;

   package Context_Vectors is new Ada.Containers.Vectors
     (Index_Type => Natural, Element_Type => Context_Entry);

   function Build_Context (Root : XML_Node_Access) return Context_Vectors.Vector is
      Result  : Context_Vectors.Vector;
      Context : constant XML_Node_Access := Child (Root, "context");
   begin
      for Context_Item of Context.Children loop
         if To_String (Context_Item.Tag) = "entry" then
            Require
              (Natural'Value (Child_Text (Context_Item, "UID")) > 0,
               "invalid SANY UID");
            Require
              (Context_Item.Children.Length = 2,
               "malformed SANY context entry");
            Result.Append
              (Context_Entry'
                 (UID  => Natural'Value (Child_Text (Context_Item, "UID")),
                  Node => Context_Item.Children.Last_Element));
         end if;
      end loop;
      return Result;
   end Build_Context;

   function Resolve
     (Context : Context_Vectors.Vector; Reference : XML_Node_Access)
      return XML_Node_Access
   is
      UID : constant Natural := Natural'Value (Child_Text (Reference, "UID"));
   begin
      for Context_Item of Context loop
         if Context_Item.UID = UID then
            return Context_Item.Node;
         end if;
      end loop;
      raise Generation_Error with "unresolved SANY UID" & Natural'Image (UID);
   end Resolve;

   function Source_Line (Node : XML_Node_Access) return Natural is
      Location : constant XML_Node_Access := Child (Node, "location", False);
      Lines    : XML_Node_Access;
   begin
      if Location = null then
         return 0;
      end if;
      Lines := Child (Location, "line", False);
      return (if Lines = null then 0 else Natural'Value (Child_Text (Lines, "begin")));
   end Source_Line;

   function Source_Column (Node : XML_Node_Access) return Natural is
      Location : constant XML_Node_Access := Child (Node, "location", False);
      Columns  : XML_Node_Access;
   begin
      if Location = null then
         return 0;
      end if;
      Columns := Child (Location, "column", False);
      return (if Columns = null then 0 else Natural'Value (Child_Text (Columns, "begin")));
   end Source_Column;

   type Expression;
   type Expression_Access is access Expression;

   package Expression_Vectors is new Ada.Containers.Vectors
     (Index_Type => Natural, Element_Type => Expression_Access);

   type Expression_Kind is (Application, Integer_Literal, String_Literal);

   type Expression is record
      Kind     : Expression_Kind := Application;
      Name     : Unbounded_String;
      Integer  : Long_Long_Integer := 0;
      Text     : Unbounded_String;
      Arguments : Expression_Vectors.Vector;
      Line     : Natural := 0;
   end record;

   function Parse_Expression
     (Node : XML_Node_Access; Context : Context_Vectors.Vector)
      return Expression_Access
   is
      Result : constant Expression_Access := new Expression;
   begin
      Result.Line := Source_Line (Node);
      if To_String (Node.Tag) = "NumeralNode" then
         Result.Kind := Integer_Literal;
         Result.Integer := Long_Long_Integer'Value (Child_Text (Node, "IntValue"));
      elsif To_String (Node.Tag) = "StringNode" then
         Result.Kind := String_Literal;
         Result.Text := To_Unbounded_String (Child_Text (Node, "StringValue"));
      elsif To_String (Node.Tag) = "OpApplNode" then
         declare
            Operator_Wrapper : constant XML_Node_Access := Child (Node, "operator");
            Reference        : constant XML_Node_Access := First_Child (Operator_Wrapper);
            Definition       : constant XML_Node_Access := Resolve (Context, Reference);
            Operands         : constant XML_Node_Access := Child (Node, "operands", False);
         begin
            Result.Name := To_Unbounded_String (Child_Text (Definition, "uniquename"));
            if Operands /= null then
               for Operand of Operands.Children loop
                  Result.Arguments.Append (Parse_Expression (Operand, Context));
               end loop;
            end if;
         end;
      elsif Ada.Strings.Fixed.Tail (To_String (Node.Tag), 3) = "Ref" then
         Result.Name := To_Unbounded_String
           (Child_Text (Resolve (Context, Node), "uniquename"));
      else
         raise Generation_Error with "unsupported SANY expression node " & To_String (Node.Tag);
      end if;
      return Result;
   end Parse_Expression;

   type Type_Descriptor;
   type Type_Access is access Type_Descriptor;

   type Field_Descriptor is record
      TLA_Name   : Unbounded_String;
      Ada_Name   : Unbounded_String;
      Value_Type : Type_Access;
      Line       : Natural := 0;
      Column     : Natural := 0;
   end record;

   package Field_Vectors is new Ada.Containers.Vectors
     (Index_Type => Natural, Element_Type => Field_Descriptor);

   package String_Vectors is new Ada.Containers.Vectors
     (Index_Type => Natural, Element_Type => Unbounded_String);

   type Type_Kind is (Boolean_Type, Integer_Range_Type, Enumeration_Type, Record_Type);

   type Type_Descriptor is record
      Kind     : Type_Kind := Boolean_Type;
      Low      : Long_Long_Integer := 0;
      High     : Long_Long_Integer := 0;
      Literals : String_Vectors.Vector;
      Fields   : Field_Vectors.Vector;
      Line     : Natural := 0;
   end record;

   function Is_Ada_Reserved (Name : String) return Boolean is
      Lower : constant String := Ada.Characters.Handling.To_Lower (Name);
   begin
      return Lower in
        "abort" | "abs" | "abstract" | "accept" | "access" | "aliased" |
        "all" | "and" | "array" | "at" | "begin" | "body" | "case" |
        "constant" | "declare" | "delay" | "delta" | "digits" | "do" |
        "else" | "elsif" | "end" | "entry" | "exception" | "exit" |
        "for" | "function" | "generic" | "goto" | "if" | "in" |
        "interface" | "is" | "limited" | "loop" | "mod" | "new" |
        "not" | "null" | "of" | "or" | "others" | "out" | "overriding" |
        "package" | "parallel" | "pragma" | "private" | "procedure" |
        "protected" | "raise" | "range" | "record" | "rem" | "renames" |
        "requeue" | "return" | "reverse" | "select" | "separate" |
        "some" | "subtype" | "synchronized" | "tagged" | "task" |
        "terminate" | "then" | "type" | "until" | "use" | "when" |
        "while" | "with" | "xor";
   end Is_Ada_Reserved;

   function Ada_Name (Name : String) return String is
      Result         : Unbounded_String;
      Previous_Lower : Boolean := False;
      Previous_Sep   : Boolean := True;
   begin
      for Item of Name loop
         if Item in 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' then
            if Item in 'A' .. 'Z' and then Previous_Lower and then not Previous_Sep then
               Append (Result, '_');
            end if;
            if Previous_Sep or else Length (Result) = 0 then
               Append (Result, Ada.Characters.Handling.To_Upper (Item));
            else
               Append (Result, Item);
            end if;
            Previous_Lower := Item in 'a' .. 'z';
            Previous_Sep := False;
         elsif not Previous_Sep and then Length (Result) > 0 then
            Append (Result, '_');
            Previous_Lower := False;
            Previous_Sep := True;
         end if;
      end loop;
      while Length (Result) > 0 and then Element (Result, Length (Result)) = '_' loop
         Delete (Result, Length (Result), Length (Result));
      end loop;
      Require (Length (Result) > 0, "TLA+ name cannot become an Ada identifier: " & Name);
      if Element (Result, 1) in '0' .. '9' or else Is_Ada_Reserved (To_String (Result)) then
         return "TLA_" & To_String (Result);
      end if;
      return To_String (Result);
   end Ada_Name;

   function Ada_String_Literal (Value : String) return String is
      Result : Unbounded_String := To_Unbounded_String ("""");
   begin
      for Item of Value loop
         if Item = '"' then
            Append (Result, """");
         end if;
         Append (Result, Item);
      end loop;
      Append (Result, '"');
      return To_String (Result);
   end Ada_String_Literal;

   function Is_Ada_Identifier (Value : String) return Boolean is
      Previous_Underscore : Boolean := False;
   begin
      if Value'Length = 0
        or else not Ada.Characters.Handling.Is_Letter (Value (Value'First))
        or else Is_Ada_Reserved (Value)
      then
         return False;
      end if;
      for Item of Value loop
         if not Ada.Characters.Handling.Is_Alphanumeric (Item) and then Item /= '_' then
            return False;
         elsif Item = '_' and then Previous_Underscore then
            return False;
         end if;
         Previous_Underscore := Item = '_';
      end loop;
      return not Previous_Underscore;
   end Is_Ada_Identifier;

   procedure Validate_Generated_Names
     (Item : Type_Access; Context_Name : String)
   is
   begin
      if Item.Kind = Enumeration_Type then
         for Left in Item.Literals.First_Index .. Item.Literals.Last_Index loop
            for Right in Left + 1 .. Item.Literals.Last_Index loop
               Require
                 (Ada.Characters.Handling.To_Lower
                    (Ada_Name (To_String (Item.Literals (Left))))
                  /= Ada.Characters.Handling.To_Lower
                    (Ada_Name (To_String (Item.Literals (Right)))),
                  "enumeration literals collide as Ada identifiers in " & Context_Name);
            end loop;
         end loop;
      elsif Item.Kind = Record_Type then
         for Left in Item.Fields.First_Index .. Item.Fields.Last_Index loop
            for Right in Left + 1 .. Item.Fields.Last_Index loop
               Require
                 (Ada.Characters.Handling.To_Lower
                    (To_String (Item.Fields (Left).Ada_Name))
                  /= Ada.Characters.Handling.To_Lower
                    (To_String (Item.Fields (Right).Ada_Name)),
                  "record fields collide as Ada identifiers in " & Context_Name);
            end loop;
            Validate_Generated_Names
              (Item.Fields (Left).Value_Type,
               Context_Name & "." & To_String (Item.Fields (Left).TLA_Name));
         end loop;
      end if;
   end Validate_Generated_Names;

   function Type_From_Set (Expr : Expression_Access) return Type_Access is
      Result : constant Type_Access := new Type_Descriptor;
      Name   : constant String := To_String (Expr.Name);
   begin
      Result.Line := Expr.Line;
      if Expr.Kind = Application and then Name = "BOOLEAN" and then Expr.Arguments.Is_Empty then
         Result.Kind := Boolean_Type;
      elsif Expr.Kind = Application and then Name = ".." and then Expr.Arguments.Length = 2 then
         Require
           (Expr.Arguments.First_Element.Kind = Integer_Literal
            and then Expr.Arguments.Last_Element.Kind = Integer_Literal,
            "integer range bounds must be literals at line" & Natural'Image (Expr.Line));
         Result.Kind := Integer_Range_Type;
         Result.Low := Expr.Arguments.First_Element.Integer;
         Result.High := Expr.Arguments.Last_Element.Integer;
         Require (Result.Low <= Result.High, "reversed integer range at line" & Natural'Image (Expr.Line));
      elsif Expr.Kind = Application and then Name = "$SetEnumerate" then
         Require (not Expr.Arguments.Is_Empty, "cannot infer the type of an empty set");
         Result.Kind := Enumeration_Type;
         for Literal of Expr.Arguments loop
            Require
              (Literal.Kind = String_Literal,
               "only finite string sets map to Ada enumerations at line" & Natural'Image (Expr.Line));
            Result.Literals.Append (Literal.Text);
         end loop;
      elsif Expr.Kind = Application and then Name = "$SetOfRcds" then
         Require (not Expr.Arguments.Is_Empty, "empty record type at line" & Natural'Image (Expr.Line));
         Result.Kind := Record_Type;
         for Pair of Expr.Arguments loop
            Require
              (Pair.Kind = Application
               and then To_String (Pair.Name) = "$Pair"
               and then Pair.Arguments.Length = 2
               and then Pair.Arguments.First_Element.Kind = String_Literal,
               "malformed record type at line" & Natural'Image (Expr.Line));
            declare
               Field_Name : constant String := To_String (Pair.Arguments.First_Element.Text);
            begin
            Result.Fields.Append
                 (Field_Descriptor'
                    (TLA_Name   => To_Unbounded_String (Field_Name),
                     Ada_Name   => To_Unbounded_String (Ada_Name (Field_Name)),
                     Value_Type => Type_From_Set (Pair.Arguments.Last_Element),
                     Line       => Pair.Line,
                     Column     => 0));
            end;
         end loop;
      else
         raise Generation_Error
           with "no exact Ada representation for TLA+ type operator '"
           & (if Name'Length = 0 then "<literal>" else Name)
           & "' at line" & Natural'Image (Expr.Line)
           & "; add a finite bound or a supported explicit type set";
      end if;
      return Result;
   end Type_From_Set;

   function Find_Root_Module
     (Context : Context_Vectors.Vector; Root_Name : String) return XML_Node_Access
   is
   begin
      for Context_Item of Context loop
         if To_String (Context_Item.Node.Tag) = "ModuleNode"
           and then Child_Text (Context_Item.Node, "uniquename") = Root_Name
         then
            return Context_Item.Node;
         end if;
      end loop;
      raise Generation_Error with "SANY XML lacks root module " & Root_Name;
   end Find_Root_Module;

   function Find_Definition
     (Module_Node : XML_Node_Access;
      Context     : Context_Vectors.Vector;
      Name        : String) return XML_Node_Access
   is
   begin
      for Reference of Module_Node.Children loop
         if To_String (Reference.Tag) = "UserDefinedOpKindRef" then
            declare
               Definition : constant XML_Node_Access := Resolve (Context, Reference);
            begin
               if Child_Text (Definition, "uniquename") = Name then
                  return Definition;
               end if;
            end;
         end if;
      end loop;
      raise Generation_Error
        with "root module lacks required type operator " & Name;
   end Find_Definition;

   function Definition_Expression
     (Module_Node : XML_Node_Access;
      Context     : Context_Vectors.Vector;
      Name        : String) return Expression_Access
   is
      Definition : constant XML_Node_Access := Find_Definition (Module_Node, Context, Name);
      Body_Node  : constant XML_Node_Access := Child (Definition, "body");
   begin
      Require
        (Child_Text (Definition, "arity") = "0",
         "type operator " & Name & " must accept no parameters");
      return Parse_Expression (First_Child (Body_Node), Context);
   end Definition_Expression;

   procedure Sort_Fields_By_Source (Fields : in out Field_Vectors.Vector) is
   begin
      if Fields.Length < 2 then
         return;
      end if;
      for Right in Fields.First_Index + 1 .. Fields.Last_Index loop
         declare
            Item : constant Field_Descriptor := Fields (Right);
            Left : Natural := Right;
         begin
            while Left > Fields.First_Index
              and then
                (Fields (Left - 1).Line > Item.Line
                 or else
                   (Fields (Left - 1).Line = Item.Line
                    and then Fields (Left - 1).Column > Item.Column))
            loop
               Fields.Replace_Element (Left, Fields (Left - 1));
               Left := Left - 1;
            end loop;
            Fields.Replace_Element (Left, Item);
         end;
      end loop;
   end Sort_Fields_By_Source;

   function State_Fields
     (Module_Node : XML_Node_Access; Context : Context_Vectors.Vector)
      return Field_Vectors.Vector
   is
      Result : Field_Vectors.Vector;
   begin
      for Reference of Module_Node.Children loop
         if To_String (Reference.Tag) = "OpDeclNodeRef" then
            declare
               Declaration : constant XML_Node_Access := Resolve (Context, Reference);
               Name        : constant String := Child_Text (Declaration, "uniquename");
            begin
               if Child_Text (Declaration, "kind") = "3" then
                  Result.Append
                    (Field_Descriptor'
                       (TLA_Name   => To_Unbounded_String (Name),
                        Ada_Name   => To_Unbounded_String (Ada_Name (Name)),
                        Value_Type => null,
                        Line       => Source_Line (Declaration),
                        Column     => Source_Column (Declaration)));
               end if;
            end;
         end if;
      end loop;
      Sort_Fields_By_Source (Result);
      Require (not Result.Is_Empty, "root module declares no state variables");
      return Result;
   end State_Fields;

   procedure Apply_State_Constraint
     (Constraint : Expression_Access; Fields : in out Field_Vectors.Vector)
   is
      Name : constant String := To_String (Constraint.Name);
   begin
      if Constraint.Kind = Application and then Name in "\land" | "$ConjList" then
         for Argument of Constraint.Arguments loop
            Apply_State_Constraint (Argument, Fields);
         end loop;
         return;
      end if;
      Require
        (Constraint.Kind = Application
         and then Name = "\in"
         and then Constraint.Arguments.Length = 2
         and then Constraint.Arguments.First_Element.Kind = Application
         and then Constraint.Arguments.First_Element.Arguments.Is_Empty,
         "state type invariant must be a conjunction of 'variable \in TypeSet' constraints at line"
         & Natural'Image (Constraint.Line));
      declare
         Variable_Name : constant String := To_String (Constraint.Arguments.First_Element.Name);
         Found         : Boolean := False;
      begin
         for Index in Fields.First_Index .. Fields.Last_Index loop
            if To_String (Fields (Index).TLA_Name) = Variable_Name then
               Require
                 (Fields (Index).Value_Type = null,
                  "duplicate type constraint for " & Variable_Name);
               declare
                  Updated : Field_Descriptor := Fields (Index);
               begin
                  Updated.Value_Type := Type_From_Set (Constraint.Arguments.Last_Element);
                  Fields.Replace_Element (Index, Updated);
               end;
               Found := True;
               exit;
            end if;
         end loop;
         Require (Found, "type invariant constrains non-variable " & Variable_Name);
      end;
   end Apply_State_Constraint;

   function Image (Value : Long_Long_Integer) return String is
     (Ada.Strings.Fixed.Trim (Long_Long_Integer'Image (Value), Ada.Strings.Both));

   function Type_Description (Item : Type_Access) return String is
   begin
      case Item.Kind is
         when Boolean_Type =>
            return "boolean";
         when Integer_Range_Type =>
            return "integer-range(" & Image (Item.Low) & ".." & Image (Item.High) & ")";
         when Enumeration_Type =>
            return "finite-string-enum";
         when Record_Type =>
            return "record";
      end case;
   end Type_Description;

   procedure Put_Type_Declarations
     (Output : in out Ada.Text_IO.File_Type;
      Prefix : String;
      Item   : Type_Access);

   function Ada_Type_Name (Prefix : String; Item : Type_Access) return String is
     (if Item.Kind = Boolean_Type then "Boolean" else Prefix & "_Type");

   procedure Put_Type_Declarations
     (Output : in out Ada.Text_IO.File_Type;
      Prefix : String;
      Item   : Type_Access)
   is
   begin
      case Item.Kind is
         when Boolean_Type =>
            null;
         when Integer_Range_Type =>
            Ada.Text_IO.Put_Line
              (Output,
               "   type " & Prefix & "_Type is range "
               & Image (Item.Low) & " .. " & Image (Item.High) & ";");
         when Enumeration_Type =>
            Ada.Text_IO.Put_Line (Output, "   type " & Prefix & "_Type is");
            Ada.Text_IO.Put (Output, "     (");
            for Index in Item.Literals.First_Index .. Item.Literals.Last_Index loop
               if Index > Item.Literals.First_Index then
                  Ada.Text_IO.Put_Line (Output, ",");
                  Ada.Text_IO.Put (Output, "      ");
               end if;
               Ada.Text_IO.Put
                 (Output,
                  Prefix & "_" & Ada_Name (To_String (Item.Literals (Index))));
            end loop;
            Ada.Text_IO.Put_Line (Output, ");");
         when Record_Type =>
            for Field of Item.Fields loop
               Put_Type_Declarations
                 (Output, Prefix & "_" & To_String (Field.Ada_Name), Field.Value_Type);
            end loop;
            Ada.Text_IO.Put_Line (Output, "   type " & Prefix & "_Type is record");
            for Field of Item.Fields loop
               Ada.Text_IO.Put_Line
                 (Output,
                  "      " & To_String (Field.Ada_Name) & " : "
                  & Ada_Type_Name
                      (Prefix & "_" & To_String (Field.Ada_Name), Field.Value_Type)
                  & ";");
            end loop;
            Ada.Text_IO.Put_Line (Output, "   end record;");
      end case;
   end Put_Type_Declarations;

   procedure Put_Codec_Declarations
     (Output : in out Ada.Text_IO.File_Type;
      Prefix : String;
      Item   : Type_Access)
   is
      Type_Name : constant String := Ada_Type_Name (Prefix, Item);
   begin
      if Item.Kind = Record_Type then
         for Field of Item.Fields loop
            Put_Codec_Declarations
              (Output, Prefix & "_" & To_String (Field.Ada_Name), Field.Value_Type);
         end loop;
      end if;
      Ada.Text_IO.Put_Line
        (Output,
         "   function Decode_" & Prefix);
      Ada.Text_IO.Put_Line (Output, "     (Source : String;");
      Ada.Text_IO.Put_Line
        (Output,
         "      Limits : Flyology_TLA.Traces.Load_Limits) return "
         & Type_Name & ";");
      Ada.Text_IO.Put_Line
        (Output,
         "   function Encode_" & Prefix & " (Item : " & Type_Name & ") return String;");
   end Put_Codec_Declarations;

   procedure Put_Codec_Body
     (Output : in out Ada.Text_IO.File_Type;
      Prefix : String;
      Item   : Type_Access)
   is
      Type_Name : constant String := Ada_Type_Name (Prefix, Item);
   begin
      if Item.Kind = Record_Type then
         for Field of Item.Fields loop
            Put_Codec_Body
              (Output, Prefix & "_" & To_String (Field.Ada_Name), Field.Value_Type);
         end loop;
      end if;
      Ada.Text_IO.New_Line (Output);
      Ada.Text_IO.Put_Line
        (Output,
         "   function Decode_" & Prefix);
      Ada.Text_IO.Put_Line (Output, "     (Source : String;");
      Ada.Text_IO.Put_Line
        (Output,
         "      Limits : Flyology_TLA.Traces.Load_Limits) return "
         & Type_Name & " is");
      begin
         case Item.Kind is
            when Boolean_Type =>
               Ada.Text_IO.Put_Line (Output, "      pragma Unreferenced (Limits);");
               Ada.Text_IO.Put_Line (Output, "   begin");
               Ada.Text_IO.Put_Line
                 (Output, "      return Flyology_TLA.Codecs.Decode_Boolean (Source);");
            when Integer_Range_Type =>
               Ada.Text_IO.Put_Line (Output, "      pragma Unreferenced (Limits);");
               Ada.Text_IO.Put_Line (Output, "   begin");
               Ada.Text_IO.Put_Line
                 (Output,
                  "      return " & Type_Name
                  & " (Flyology_TLA.Codecs.Decode_Integer (Source));");
            when Enumeration_Type =>
               Ada.Text_IO.Put_Line (Output, "      pragma Unreferenced (Limits);");
               Ada.Text_IO.Put_Line
                 (Output,
                  "      Value : constant String := Flyology_TLA.Codecs.Decode_String (Source);");
               Ada.Text_IO.Put_Line (Output, "   begin");
               for Index in Item.Literals.First_Index .. Item.Literals.Last_Index loop
                  Ada.Text_IO.Put_Line
                    (Output,
                     (if Index = Item.Literals.First_Index then "      if " else "      elsif ")
                     & "Value = "
                     & Ada_String_Literal (To_String (Item.Literals (Index)))
                     & " then");
                  Ada.Text_IO.Put_Line
                    (Output,
                     "         return " & Prefix & "_"
                     & Ada_Name (To_String (Item.Literals (Index))) & ";");
               end loop;
               Ada.Text_IO.Put_Line (Output, "      end if;");
               Ada.Text_IO.Put_Line
                 (Output,
                  "      raise Flyology_TLA.Codecs.Codec_Error with "
                  & Ada_String_Literal ("unknown " & Prefix & " literal") & ";");
            when Record_Type =>
               Ada.Text_IO.Put_Line (Output, "   begin");
               Ada.Text_IO.Put_Line
                 (Output,
                  "      if Flyology_TLA.Codecs.Object_Size (Source, Limits) /= "
                  & Ada.Strings.Fixed.Trim
                      (Natural'Image (Natural (Item.Fields.Length)), Ada.Strings.Both)
                  & " then");
               Ada.Text_IO.Put_Line
                 (Output,
                  "         raise Flyology_TLA.Codecs.Codec_Error with "
                  & Ada_String_Literal ("unexpected " & Prefix & " object shape")
                  & ";");
               Ada.Text_IO.Put_Line (Output, "      end if;");
               Ada.Text_IO.Put_Line (Output, "      return");
               Ada.Text_IO.Put_Line (Output, "        (");
               for Index in Item.Fields.First_Index .. Item.Fields.Last_Index loop
                  declare
                     Field : constant Field_Descriptor := Item.Fields (Index);
                     Field_Prefix : constant String := Prefix & "_" & To_String (Field.Ada_Name);
                  begin
                     Ada.Text_IO.Put
                       (Output,
                        "         " & To_String (Field.Ada_Name) & " => Decode_"
                        & Field_Prefix & ASCII.LF
                        & "           (Flyology_TLA.Codecs.Object_Member (Source, "
                        & Ada_String_Literal (To_String (Field.TLA_Name))
                        & ", Limits), Limits)");
                     Ada.Text_IO.Put_Line
                       (Output, (if Index = Item.Fields.Last_Index then ");" else ","));
                  end;
               end loop;
         end case;
      end;
      Ada.Text_IO.Put_Line (Output, "   end Decode_" & Prefix & ";");

      Ada.Text_IO.New_Line (Output);
      Ada.Text_IO.Put_Line
        (Output,
         "   function Encode_" & Prefix & " (Item : " & Type_Name & ") return String is");
      case Item.Kind is
         when Boolean_Type =>
            Ada.Text_IO.Put_Line
              (Output, "     (Flyology_TLA.Codecs.Encode_Boolean (Item));");
         when Integer_Range_Type =>
            Ada.Text_IO.Put_Line
              (Output, "     (Flyology_TLA.Codecs.Encode_Integer (Long_Long_Integer (Item)));");
         when Enumeration_Type =>
            Ada.Text_IO.Put_Line (Output, "   begin");
            Ada.Text_IO.Put_Line (Output, "      return");
            Ada.Text_IO.Put_Line (Output, "        (case Item is");
            for Index in Item.Literals.First_Index .. Item.Literals.Last_Index loop
               Ada.Text_IO.Put_Line
                 (Output,
                  "            when " & Prefix & "_"
                  & Ada_Name (To_String (Item.Literals (Index))) & " => "
                  & Ada_String_Literal
                      (Flyology_TLA.Codecs.Encode_String (To_String (Item.Literals (Index))))
                  & (if Index = Item.Literals.Last_Index then ");" else ","));
            end loop;
            Ada.Text_IO.Put_Line (Output, "   end Encode_" & Prefix & ";");
            return;
         when Record_Type =>
            Ada.Text_IO.Put_Line (Output, "   begin");
            Ada.Text_IO.Put_Line (Output, "      return");
            Ada.Text_IO.Put (Output, "        ""{""");
            for Index in Item.Fields.First_Index .. Item.Fields.Last_Index loop
               declare
                  Field : constant Field_Descriptor := Item.Fields (Index);
               begin
               Ada.Text_IO.Put_Line (Output, " &");
               Ada.Text_IO.Put_Line
                 (Output,
                  "        Flyology_TLA.Codecs.Encode_String ("
                  & Ada_String_Literal (To_String (Field.TLA_Name)) & ") & "":""");
               Ada.Text_IO.Put
                 (Output,
                  "        & Encode_" & Prefix & "_" & To_String (Field.Ada_Name)
                  & " (Item." & To_String (Field.Ada_Name) & ")");
               if Index /= Item.Fields.Last_Index then
                  Ada.Text_IO.Put (Output, " & "",""");
               end if;
               end;
            end loop;
            Ada.Text_IO.Put_Line (Output, " & ""}"";");
            Ada.Text_IO.Put_Line (Output, "   end Encode_" & Prefix & ";");
            return;
      end case;
   end Put_Codec_Body;

   procedure Write_Generated_Spec
     (Path          : String;
      Package_Name  : String;
      Source_SHA256 : String;
      Config_SHA256 : String;
      State         : Type_Access;
      Input         : Type_Access;
      Outcome       : Type_Access)
   is
      Output : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Create (Output, Ada.Text_IO.Out_File, Path);
      Ada.Text_IO.Put_Line (Output, "--  Generated by flyology-tla; do not edit.");
      Ada.Text_IO.Put_Line (Output, "--  TLA source SHA-256: " & Source_SHA256);
      Ada.Text_IO.Put_Line (Output, "--  TLC config SHA-256: " & Config_SHA256);
      Ada.Text_IO.Put_Line (Output, "with Flyology_TLA.Replay;");
      Ada.Text_IO.Put_Line (Output, "with Flyology_TLA.Traces;");
      Ada.Text_IO.New_Line (Output);
      Ada.Text_IO.Put_Line (Output, "package " & Package_Name & " is");
      Ada.Text_IO.New_Line (Output);
      Ada.Text_IO.Put_Line
        (Output,
         "   --  Types below come from the reviewed finite TLA+ type operators.");
      Ada.Text_IO.Put_Line
        (Output,
         "   --  Trace JSON conversion stays private to this generated package.");
      Ada.Text_IO.New_Line (Output);
      Put_Type_Declarations (Output, "State", State);
      Ada.Text_IO.New_Line (Output);
      Put_Type_Declarations (Output, "Input", Input);
      Ada.Text_IO.New_Line (Output);
      Put_Type_Declarations (Output, "Outcome", Outcome);
      Ada.Text_IO.New_Line (Output);
      Ada.Text_IO.Put_Line
        (Output,
         "   --  Consumers implement this typed boundary; expected model values are");
      Ada.Text_IO.Put_Line
        (Output,
         "   --  deliberately absent, so an adapter cannot echo the oracle.");
      Ada.Text_IO.Put_Line (Output, "   type Adapter is abstract tagged limited null record;");
      Ada.Text_IO.New_Line (Output);
      Ada.Text_IO.Put_Line (Output, "   procedure Reset");
      Ada.Text_IO.Put_Line (Output, "     (Self     : in out Adapter;");
      Ada.Text_IO.Put_Line (Output, "      Observed : out State_Type;");
      Ada.Text_IO.Put_Line
        (Output, "      Status   : out Flyology_TLA.Replay.Adapter_Outcome) is abstract;");
      Ada.Text_IO.New_Line (Output);
      Ada.Text_IO.Put_Line (Output, "   procedure Apply");
      Ada.Text_IO.Put_Line (Output, "     (Self         : in out Adapter;");
      Ada.Text_IO.Put_Line (Output, "      Index        : Positive;");
      Ada.Text_IO.Put_Line (Output, "      Action       : String;");
      Ada.Text_IO.Put_Line (Output, "      Role         : String;");
      Ada.Text_IO.Put_Line (Output, "      Input        : Input_Type;");
      Ada.Text_IO.Put_Line (Output, "      Model_Source : String;");
      Ada.Text_IO.Put_Line (Output, "      Observed     : out Outcome_Type;");
      Ada.Text_IO.Put_Line (Output, "      State        : out State_Type;");
      Ada.Text_IO.Put_Line
        (Output, "      Status       : out Flyology_TLA.Replay.Adapter_Outcome) is abstract;");
      Ada.Text_IO.New_Line (Output);
      Ada.Text_IO.Put_Line
        (Output,
         "   --  Run decodes, compares structurally, and reports the first divergence.");
      Ada.Text_IO.Put_Line (Output, "   procedure Run");
      Ada.Text_IO.Put_Line (Output, "     (Self   : in out Adapter'Class;");
      Ada.Text_IO.Put_Line (Output, "      Trace  : Flyology_TLA.Traces.Trace;");
      Ada.Text_IO.Put_Line (Output, "      Limits : Flyology_TLA.Traces.Load_Limits;");
      Ada.Text_IO.Put_Line (Output, "      Result : out Flyology_TLA.Replay.Replay_Result);");
      Ada.Text_IO.New_Line (Output);
      Ada.Text_IO.Put_Line (Output, "end " & Package_Name & ";");
      Ada.Text_IO.Close (Output);
   end Write_Generated_Spec;

   procedure Write_Generated_Body
     (Path          : String;
      Package_Name  : String;
      Source_SHA256 : String;
      Config_SHA256 : String;
      State         : Type_Access;
      Input         : Type_Access;
      Outcome       : Type_Access)
   is
      Output : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Create (Output, Ada.Text_IO.Out_File, Path);
      Ada.Text_IO.Put_Line (Output, "--  Generated by flyology-tla; do not edit.");
      Ada.Text_IO.Put_Line (Output, "--  TLA source SHA-256: " & Source_SHA256);
      Ada.Text_IO.Put_Line (Output, "--  TLC config SHA-256: " & Config_SHA256);
      Ada.Text_IO.Put_Line (Output, "with Ada.Exceptions;");
      Ada.Text_IO.Put_Line (Output, "with Ada.Strings.Unbounded;");
      Ada.Text_IO.Put_Line (Output, "with Flyology_TLA.Codecs;");
      Ada.Text_IO.New_Line (Output);
      Ada.Text_IO.Put_Line (Output, "package body " & Package_Name & " is");
      Ada.Text_IO.New_Line (Output);
      Put_Codec_Declarations (Output, "State", State);
      Put_Codec_Declarations (Output, "Input", Input);
      Put_Codec_Declarations (Output, "Outcome", Outcome);
      Ada.Text_IO.Put_Line
        (Output,
         "   pragma Unreferenced (Decode_State, Encode_Input, Decode_Outcome);");
      Put_Codec_Body (Output, "State", State);
      Put_Codec_Body (Output, "Input", Input);
      Put_Codec_Body (Output, "Outcome", Outcome);
      Ada.Text_IO.New_Line (Output);
      Ada.Text_IO.Put_Line (Output, "   procedure Run");
      Ada.Text_IO.Put_Line (Output, "     (Self   : in out Adapter'Class;");
      Ada.Text_IO.Put_Line (Output, "      Trace  : Flyology_TLA.Traces.Trace;");
      Ada.Text_IO.Put_Line (Output, "      Limits : Flyology_TLA.Traces.Load_Limits;");
      Ada.Text_IO.Put_Line (Output, "      Result : out Flyology_TLA.Replay.Replay_Result)");
      Ada.Text_IO.Put_Line (Output, "   is");
      Ada.Text_IO.Put_Line
        (Output, "      use Ada.Strings.Unbounded;");
      Ada.Text_IO.Put_Line
        (Output,
         "      --  This private bridge is the only JSON-facing adapter layer.");
      Ada.Text_IO.Put_Line
        (Output,
         "      --  It decodes each command before calling the typed consumer.");
      Ada.Text_IO.Put_Line (Output, "      type Bridge is new Flyology_TLA.Replay.Adapter with null record;");
      Ada.Text_IO.New_Line (Output);
      Ada.Text_IO.Put_Line (Output, "      overriding procedure Reset");
      Ada.Text_IO.Put_Line (Output, "        (Ignored             : in out Bridge;");
      Ada.Text_IO.Put_Line (Output, "         Observed_State_JSON : out Unbounded_String;");
      Ada.Text_IO.Put_Line
        (Output, "         Status              : out Flyology_TLA.Replay.Adapter_Outcome);");
      Ada.Text_IO.New_Line (Output);
      Ada.Text_IO.Put_Line (Output, "      overriding procedure Apply");
      Ada.Text_IO.Put_Line (Output, "        (Ignored               : in out Bridge;");
      Ada.Text_IO.Put_Line (Output, "         Command               : Flyology_TLA.Replay.Replay_Command;");
      Ada.Text_IO.Put_Line (Output, "         Observed_Outcome_JSON : out Unbounded_String;");
      Ada.Text_IO.Put_Line (Output, "         Observed_State_JSON   : out Unbounded_String;");
      Ada.Text_IO.Put_Line
        (Output, "         Status                : out Flyology_TLA.Replay.Adapter_Outcome);");
      Ada.Text_IO.New_Line (Output);
      Ada.Text_IO.Put_Line (Output, "      procedure Reset");
      Ada.Text_IO.Put_Line (Output, "        (Ignored             : in out Bridge;");
      Ada.Text_IO.Put_Line (Output, "         Observed_State_JSON : out Unbounded_String;");
      Ada.Text_IO.Put_Line
        (Output, "         Status              : out Flyology_TLA.Replay.Adapter_Outcome)");
      Ada.Text_IO.Put_Line (Output, "      is");
      Ada.Text_IO.Put_Line (Output, "         pragma Unreferenced (Ignored);");
      Ada.Text_IO.Put_Line (Output, "         Observed : State_Type;");
      Ada.Text_IO.Put_Line (Output, "      begin");
      Ada.Text_IO.Put_Line (Output, "         " & Package_Name & ".Reset (Self, Observed, Status);");
      Ada.Text_IO.Put_Line (Output, "         if Status.Succeeded then");
      Ada.Text_IO.Put_Line
        (Output, "            Observed_State_JSON := To_Unbounded_String (Encode_State (Observed));");
      Ada.Text_IO.Put_Line (Output, "         else");
      Ada.Text_IO.Put_Line (Output, "            Observed_State_JSON := Null_Unbounded_String;");
      Ada.Text_IO.Put_Line (Output, "         end if;");
      Ada.Text_IO.Put_Line (Output, "      end Reset;");
      Ada.Text_IO.New_Line (Output);
      Ada.Text_IO.Put_Line (Output, "      procedure Apply");
      Ada.Text_IO.Put_Line (Output, "        (Ignored               : in out Bridge;");
      Ada.Text_IO.Put_Line (Output, "         Command               : Flyology_TLA.Replay.Replay_Command;");
      Ada.Text_IO.Put_Line (Output, "         Observed_Outcome_JSON : out Unbounded_String;");
      Ada.Text_IO.Put_Line (Output, "         Observed_State_JSON   : out Unbounded_String;");
      Ada.Text_IO.Put_Line
        (Output, "         Status                : out Flyology_TLA.Replay.Adapter_Outcome)");
      Ada.Text_IO.Put_Line (Output, "      is");
      Ada.Text_IO.Put_Line (Output, "         pragma Unreferenced (Ignored);");
      Ada.Text_IO.Put_Line (Output, "         Typed_Input   : Input_Type;");
      Ada.Text_IO.Put_Line (Output, "         Typed_Outcome : Outcome_Type;");
      Ada.Text_IO.Put_Line (Output, "         Typed_State   : State_Type;");
      Ada.Text_IO.Put_Line (Output, "      begin");
      Ada.Text_IO.Put_Line
        (Output, "         Typed_Input := Decode_Input (To_String (Command.Input_JSON), Limits);");
      Ada.Text_IO.Put_Line (Output, "         " & Package_Name & ".Apply");
      Ada.Text_IO.Put_Line (Output, "           (Self,");
      Ada.Text_IO.Put_Line (Output, "            Command.Index,");
      Ada.Text_IO.Put_Line (Output, "            To_String (Command.Action),");
      Ada.Text_IO.Put_Line (Output, "            To_String (Command.Role),");
      Ada.Text_IO.Put_Line (Output, "            Typed_Input,");
      Ada.Text_IO.Put_Line (Output, "            To_String (Command.Model_Source),");
      Ada.Text_IO.Put_Line (Output, "            Typed_Outcome,");
      Ada.Text_IO.Put_Line (Output, "            Typed_State,");
      Ada.Text_IO.Put_Line (Output, "            Status);");
      Ada.Text_IO.Put_Line (Output, "         if Status.Succeeded then");
      Ada.Text_IO.Put_Line
        (Output,
         "            Observed_Outcome_JSON := To_Unbounded_String "
         & "(Encode_Outcome (Typed_Outcome));");
      Ada.Text_IO.Put_Line
        (Output, "            Observed_State_JSON := To_Unbounded_String (Encode_State (Typed_State));");
      Ada.Text_IO.Put_Line (Output, "         else");
      Ada.Text_IO.Put_Line (Output, "            Observed_Outcome_JSON := Null_Unbounded_String;");
      Ada.Text_IO.Put_Line (Output, "            Observed_State_JSON := Null_Unbounded_String;");
      Ada.Text_IO.Put_Line (Output, "         end if;");
      Ada.Text_IO.Put_Line (Output, "      exception");
      Ada.Text_IO.Put_Line
        (Output,
         "         when Error : Flyology_TLA.Codecs.Codec_Error "
         & "| Constraint_Error =>");
      Ada.Text_IO.Put_Line (Output, "            Observed_Outcome_JSON := Null_Unbounded_String;");
      Ada.Text_IO.Put_Line (Output, "            Observed_State_JSON := Null_Unbounded_String;");
      Ada.Text_IO.Put_Line (Output, "            Status :=");
      Ada.Text_IO.Put_Line (Output, "              (Succeeded => False,");
      Ada.Text_IO.Put_Line
        (Output, "               Detail => To_Unbounded_String (Ada.Exceptions.Exception_Message (Error)));");
      Ada.Text_IO.Put_Line (Output, "      end Apply;");
      Ada.Text_IO.New_Line (Output);
      Ada.Text_IO.Put_Line (Output, "      Raw : Bridge;");
      Ada.Text_IO.Put_Line (Output, "   begin");
      Ada.Text_IO.Put_Line (Output, "      Flyology_TLA.Replay.Run (Raw, Trace, Limits, Result);");
      Ada.Text_IO.Put_Line (Output, "   end Run;");
      Ada.Text_IO.New_Line (Output);
      Ada.Text_IO.Put_Line (Output, "end " & Package_Name & ";");
      Ada.Text_IO.Close (Output);
   end Write_Generated_Body;

   procedure Write_Report
     (Path             : String;
      Module_Path      : String;
      Configuration    : String;
      Package_Name     : String;
      Type_Invariant   : String;
      Input_Operator   : String;
      Outcome_Operator : String;
      Source_SHA256    : String;
      Config_SHA256    : String;
      Semantic_SHA256  : String;
      State            : Type_Access;
      Input            : Type_Access;
      Outcome          : Type_Access)
   is
      Output : Ada.Text_IO.File_Type;
      procedure Pair (Name : String; Value : String; Last : Boolean := False) is
      begin
         Ada.Text_IO.Put
           (Output,
            Flyology_TLA.Codecs.Encode_String (Name) & ":"
            & Flyology_TLA.Codecs.Encode_String (Value)
            & (if Last then "" else ","));
      end Pair;
   begin
      Ada.Text_IO.Create (Output, Ada.Text_IO.Out_File, Path);
      Ada.Text_IO.Put (Output, "{");
      Pair ("format", "flyology.tla.ada-inference/1");
      Pair ("module_path", Module_Path);
      Pair ("configuration", Configuration);
      Pair ("package", Package_Name);
      Pair ("type_invariant", Type_Invariant);
      Pair ("input_type_operator", Input_Operator);
      Pair ("outcome_type_operator", Outcome_Operator);
      Pair ("source_sha256", Source_SHA256);
      Pair ("configuration_sha256", Config_SHA256);
      Pair ("semantic_xml_sha256", Semantic_SHA256);
      Ada.Text_IO.Put (Output, """state"":[");
      for Index in State.Fields.First_Index .. State.Fields.Last_Index loop
         declare
            Field : constant Field_Descriptor := State.Fields (Index);
         begin
            Ada.Text_IO.Put
              (Output,
               "{""variable"":"
               & Flyology_TLA.Codecs.Encode_String (To_String (Field.TLA_Name))
               & ",""ada_field"":"
               & Flyology_TLA.Codecs.Encode_String (To_String (Field.Ada_Name))
               & ",""type"":"
               & Flyology_TLA.Codecs.Encode_String (Type_Description (Field.Value_Type))
               & ",""evidence_line"":"
               & Ada.Strings.Fixed.Trim
                   (Natural'Image (Field.Value_Type.Line), Ada.Strings.Both)
               & "}"
               & (if Index = State.Fields.Last_Index then "" else ","));
         end;
      end loop;
      Ada.Text_IO.Put_Line
        (Output,
         "],""input"":" & Flyology_TLA.Codecs.Encode_String (Type_Description (Input))
         & ",""outcome"":" & Flyology_TLA.Codecs.Encode_String (Type_Description (Outcome))
         & "}");
      Ada.Text_IO.Close (Output);
   end Write_Report;

   procedure Generate
     (Module_Path           : String;
      Configuration_Path    : String;
      Type_Invariant        : String;
      Input_Type_Operator   : String;
      Outcome_Type_Operator : String;
      Package_Name          : String;
      Output_Directory      : String;
      Java_Path             : String;
      TLC_Jar_Path          : String)
   is
      Semantic_XML : Unbounded_String;
   begin
      Require
        (Ada.Directories.Kind (Java_Path) = Ada.Directories.Ordinary_File,
         "Java executable is not a file: " & Java_Path);
      Require
        (Ada.Directories.Kind (TLC_Jar_Path) = Ada.Directories.Ordinary_File,
         "TLA+ Tools jar is not a file: " & TLC_Jar_Path);
      Require
        (Is_Ada_Identifier (Package_Name),
         "generated package name must be a non-reserved simple Ada identifier");
      if not Ada.Directories.Exists (Output_Directory) then
         Ada.Directories.Create_Path (Output_Directory);
      end if;
      Semantic_XML := To_Unbounded_String
        (Flyology_TLA_Model_Identity.Export_Semantic_XML
           (Module_Path, Java_Path, TLC_Jar_Path));
      declare
         Identity      : constant Flyology_TLA_Model_Identity.Identity :=
           Flyology_TLA_Model_Identity.From_Semantic_XML
             (Module_Path, Configuration_Path, To_String (Semantic_XML));
         Source_SHA256 : constant String := To_String (Identity.Source_SHA256);
         Config_SHA256 : constant String := To_String (Identity.Configuration_SHA256);
         Semantic_Hash : constant String := To_String (Identity.Semantic_XML_SHA256);
         XML_Root       : constant XML_Node_Access := Parse_XML (To_String (Semantic_XML));
         Context        : constant Context_Vectors.Vector := Build_Context (XML_Root);
         Root_Name      : constant String := Child_Text (XML_Root, "RootModule");
         Module_Node    : constant XML_Node_Access := Find_Root_Module (Context, Root_Name);
         Fields         : Field_Vectors.Vector := State_Fields (Module_Node, Context);
         Input          : constant Type_Access :=
           Type_From_Set
             (Definition_Expression (Module_Node, Context, Input_Type_Operator));
         Outcome        : constant Type_Access :=
           Type_From_Set
             (Definition_Expression (Module_Node, Context, Outcome_Type_Operator));
         File_Stem      : constant String := Ada.Characters.Handling.To_Lower (Package_Name);
      begin
         Apply_State_Constraint
           (Definition_Expression (Module_Node, Context, Type_Invariant), Fields);
         for Field of Fields loop
            Require
              (Field.Value_Type /= null,
               "type invariant " & Type_Invariant & " does not constrain variable "
               & To_String (Field.TLA_Name));
         end loop;
         declare
            State : constant Type_Access :=
              new Type_Descriptor'
                (Kind     => Record_Type,
                 Low      => 0,
                 High     => 0,
                 Literals => <>,
                 Fields   => Fields,
                 Line     => Source_Line (Find_Definition (Module_Node, Context, Type_Invariant)));
            Spec_Path   : constant String := Output_Directory & "/" & File_Stem & ".ads";
            Body_Path   : constant String := Output_Directory & "/" & File_Stem & ".adb";
            Report_Path : constant String := Output_Directory & "/" & File_Stem & ".inference.json";
         begin
            Validate_Generated_Names (State, "state");
            Validate_Generated_Names (Input, "input");
            Validate_Generated_Names (Outcome, "outcome");
            Write_Generated_Spec
              (Spec_Path, Package_Name, Source_SHA256, Config_SHA256, State, Input, Outcome);
            Write_Generated_Body
              (Body_Path, Package_Name, Source_SHA256, Config_SHA256, State, Input, Outcome);
            Write_Report
              (Report_Path,
               Ada.Directories.Simple_Name (Module_Path),
               Ada.Directories.Simple_Name (Configuration_Path),
               Package_Name,
               Type_Invariant,
               Input_Type_Operator,
               Outcome_Type_Operator,
               Source_SHA256,
               Config_SHA256,
               Semantic_Hash,
               State,
               Input,
               Outcome);
         end;
      end;
   end Generate;

end Flyology_TLA_Ada_Generation;
