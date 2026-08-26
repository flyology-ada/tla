with Ada.Strings.Unbounded;
with Flyology_TLA.Replay;
with Flyology_TLA.Traces;

package Flyology_TLA.Command_Line is

   --  This package owns reusable harness options. Consumers can register
   --  additional value-free flags without weakening unknown-option checks.
   type Output_Format is (Terse_Output, Verbose_Output, JSON_Output);

   type Application_Flag is private;
   type Application_Flag_Array is array (Positive range <>) of Application_Flag;

   function Flag (Name : String; Description : String) return Application_Flag;
   function Is_Set (Item : Application_Flag) return Boolean;

   type Configuration is private;

   function Parse
     (Default_Limits : Flyology_TLA.Traces.Load_Limits) return Configuration;

   function Parse
     (Default_Limits   : Flyology_TLA.Traces.Load_Limits;
      Application_Flags : in out Application_Flag_Array) return Configuration;
   --  Default_Limits are application policy; explicit CLI options override
   --  individual fields. The library supplies no implicit resource limits.

   function Help_Requested (Item : Configuration) return Boolean;
   function Trace_Path (Item : Configuration) return String;
   function Limits
     (Item : Configuration) return Flyology_TLA.Traces.Load_Limits;
   function Format (Item : Configuration) return Output_Format;
   function Result_JSON_Path (Item : Configuration) return String;

   function Load
     (Item : in out Configuration) return Flyology_TLA.Traces.Trace;
   --  Load retains the hash of the exact parsed bytes for later JSON output.

   procedure Report
     (Config : Configuration;
      Result : Flyology_TLA.Replay.Replay_Result);

   procedure Set_Exit_Status (Result : Flyology_TLA.Replay.Replay_Result);

   procedure Put_Help;
   procedure Put_Help (Application_Flags : Application_Flag_Array);
   procedure Fail (Message : String; Show_Help : Boolean := False);
   procedure Fail
     (Message           : String;
      Application_Flags : Application_Flag_Array;
      Show_Help         : Boolean := False);

   Usage_Error : exception;

private

   type Application_Flag is record
      Name        : Ada.Strings.Unbounded.Unbounded_String;
      Description : Ada.Strings.Unbounded.Unbounded_String;
      Present     : Boolean := False;
   end record;

   type Configuration is record
      Input_Path       : Ada.Strings.Unbounded.Unbounded_String;
      JSON_Path        : Ada.Strings.Unbounded.Unbounded_String;
      Selected_Format  : Output_Format := Terse_Output;
      Selected_Limits  : Flyology_TLA.Traces.Load_Limits;
      Trace_SHA256     : Ada.Strings.Unbounded.Unbounded_String;
      Show_Help        : Boolean := False;
   end record;

end Flyology_TLA.Command_Line;
