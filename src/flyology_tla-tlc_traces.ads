with Flyology_TLA.Traces;

package Flyology_TLA.TLC_Traces is

   procedure Normalize
     (Raw_Path           : String;
      Output_Path        : String;
      Module_Name        : String;
      Configuration      : String;
      Source_SHA256      : String;
      Configuration_SHA256 : String;
      Toolchain_Identity : String;
      Limits             : Flyology_TLA.Traces.Load_Limits);

end Flyology_TLA.TLC_Traces;
