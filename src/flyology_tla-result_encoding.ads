with Flyology_TLA.Replay;

private package Flyology_TLA.Result_Encoding is

   function JSON_Image
     (Item         : Flyology_TLA.Replay.Replay_Result;
      Trace_SHA256 : String) return String;

end Flyology_TLA.Result_Encoding;
