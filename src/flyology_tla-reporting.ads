with Ada.Text_IO;
with Flyology_TLA.Replay;

package Flyology_TLA.Reporting is

   --  Human reports are deterministic diagnostics, not machine contracts.
   --  Use the JSON operations for the versioned result representation.
   type Verbosity is (Terse, Verbose);

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

end Flyology_TLA.Reporting;
