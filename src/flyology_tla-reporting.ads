with Ada.Text_IO;
with Ada.Strings.Unbounded;
with Flyology_TLA.Replay;
with Flyology_TLA.Traces;

package Flyology_TLA.Reporting is

   --  Human reports are deterministic diagnostics, not machine contracts.
   --  Use the JSON operations for the versioned result representation.
   type Verbosity is (Terse, Verbose);

   function Parse_JSON
     (Source       : String;
      Limits       : Flyology_TLA.Traces.Load_Limits;
      Trace_SHA256 : out Ada.Strings.Unbounded.Unbounded_String)
      return Flyology_TLA.Replay.Replay_Result;
   --  Strictly decode flyology.tla.result/1 and return its referenced trace.

   function Image
     (Result : Flyology_TLA.Replay.Replay_Result;
      Level  : Verbosity) return String;

   function JSON_Image
     (Result       : Flyology_TLA.Replay.Replay_Result;
      Trace_SHA256 : String) return String;
   --  Trace_SHA256 identifies the exact bytes replayed by the caller.

   procedure Put
     (Result : Flyology_TLA.Replay.Replay_Result;
      Level  : Verbosity);

   procedure Put
     (File   : Ada.Text_IO.File_Type;
      Result : Flyology_TLA.Replay.Replay_Result;
      Level  : Verbosity);

   procedure Put_JSON
     (Result       : Flyology_TLA.Replay.Replay_Result;
      Trace_SHA256 : String);

   procedure Put_JSON
     (File         : Ada.Text_IO.File_Type;
      Result       : Flyology_TLA.Replay.Replay_Result;
      Trace_SHA256 : String);

   procedure Write_JSON
     (Result       : Flyology_TLA.Replay.Replay_Result;
      Trace_SHA256 : String;
      Path         : String);

   Result_Error : exception;

end Flyology_TLA.Reporting;
