with Ada.Command_Line;
with Ada.Directories;
with Ada.Environment_Variables;
with GNAT.OS_Lib;

package body Flyology_TLA.Toolchains is

   function Toolchain_Script return String is
      use Ada.Directories;
      Command_Directory : constant String :=
        Containing_Directory (Full_Name (Ada.Command_Line.Command_Name));

      function Candidate (Relative_Path : String) return String is
        (Full_Name (Command_Directory & "/" & Relative_Path));

      function Usable (Path : String) return Boolean is
        (Exists (Path) and then Kind (Path) = Ordinary_File);
   begin
      if Ada.Environment_Variables.Exists ("FLYOLOGY_TLA_TOOLCHAIN_SCRIPT") then
         declare
            Path : constant String :=
              Ada.Environment_Variables.Value ("FLYOLOGY_TLA_TOOLCHAIN_SCRIPT");
         begin
            if not Usable (Path) then
               raise Program_Error with
                 "FLYOLOGY_TLA_TOOLCHAIN_SCRIPT is not a regular file: " & Path;
            end if;
            return Path;
         end;
      end if;
      if Usable (Candidate ("../share/toolchain.sh")) then
         return Candidate ("../share/toolchain.sh");
      elsif Usable (Candidate ("../share/flyology_tla/share/toolchain.sh")) then
         return Candidate ("../share/flyology_tla/share/toolchain.sh");
      elsif Usable (Candidate ("../share/flyology_tla/toolchain.sh")) then
         return Candidate ("../share/flyology_tla/toolchain.sh");
      end if;
      raise Program_Error with
        "cannot locate toolchain.sh; set FLYOLOGY_TLA_TOOLCHAIN_SCRIPT";
   end Toolchain_Script;

   procedure Dispatch is
      use GNAT.OS_Lib;
      Count  : constant Natural := Ada.Command_Line.Argument_Count - 1;
      Args   : Argument_List (1 .. Count + 1);
      Status : Integer;
   begin
      Args (1) := new String'(Toolchain_Script);
      if Count > 0 then
         for Offset in 1 .. Count loop
            Args (Offset + 1) :=
              new String'(Ada.Command_Line.Argument (Offset + 1));
         end loop;
      end if;
      Status := Spawn ("/bin/sh", Args);
      for Index in Args'Range loop
         Free (Args (Index));
      end loop;
      if Status /= 0 then
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Exit_Status (Status));
      end if;
   end Dispatch;

end Flyology_TLA.Toolchains;
