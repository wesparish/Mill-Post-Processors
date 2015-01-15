/**
  Copyright (C) 2012-2013 by Autodesk, Inc.
  All rights reserved.

  Datron MCR post processor configuration.

  $Revision: 33648 $
  $Date: 2013-01-11 12:40:00 +0100 (fr, 11 jan 2013) $
  
  FORKID {AE3BAEB9-024D-4b56-A496-49394B0BA034}
*/

description = "Datron MCR German";
vendor = "Autodesk, Inc.";
vendorUrl = "http://www.hsmworks.com";
legal = "Copyright (C) 2012-2013 by Autodesk, Inc.";
certificationLevel = 2;
minimumRevision = 24000;

extension = "mcr";
setCodePage("ascii");

tolerance = spatial(0.002, MM);

minimumChordLength = spatial(0.01, MM);
minimumCircularRadius = spatial(0.01, MM);
maximumCircularRadius = spatial(1000, MM);
minimumCircularSweep = toRad(0.01);
maximumCircularSweep = toRad(180);
allowHelicalMoves = true;
allowedCircularPlanes = undefined; // allow any circular motion



// user-defined properties
properties = {
  writeMachine: true, // write machine
  writeTools: true // writes the tools
};

var numberOfToolSlots = 9999;

var WARNING_WORK_OFFSET = 0;
var WARNING_COOLANT = 1;



var xyzFormat = createFormat({decimals:3});
var angleFormat = createFormat({decimals:3, scale:DEG});
var feedFormat = createFormat({decimals:1, scale:0.001});
var toolFormat = createFormat({decimals:0});
var rpmFormat = createFormat({decimals:0, scale:0.001});
var secFormat = createFormat({decimals:3});
var taperFormat = createFormat({decimals:1, scale:DEG});

var xOutput = createVariable({force:true}, xyzFormat);
var yOutput = createVariable({force:true}, xyzFormat);
var zOutput = createVariable({force:true}, xyzFormat);
var feedOutput = createVariable({}, feedFormat);

// collected state

/**
  Output a comment.
*/
function writeComment(text) {
  writeln("! " + text);
}

function onOpen() {
  writeln("_sprache 0;");
  
  if (programName) {
    writeComment(programName);
  }
  if (programComment) {
    writeComment(programComment);
  }

  { // stock - workpiece
    var workpiece = getWorkpiece();
    var delta = Vector.diff(workpiece.upper, workpiece.lower);
    if (delta.isNonZero()) {
      writeln("Wdef " + xyzFormat.format(delta.x) + "," + xyzFormat.format(delta.y) + "," + xyzFormat.format(delta.z) + "," + xyzFormat.format(workpiece.lower.x) + "," + xyzFormat.format(workpiece.lower.y) + "," + xyzFormat.format(workpiece.upper.z) + ",0;");
    }
  }

  // dump machine configuration
  var vendor = machineConfiguration.getVendor();
  var model = machineConfiguration.getModel();
  var description = machineConfiguration.getDescription();

  if (properties.writeMachine && (vendor || model || description)) {
    writeComment(localize("Machine"));
    if (vendor) {
      writeComment("  " + localize("vendor") + ": " + vendor);
    }
    if (model) {
      writeComment("  " + localize("model") + ": " + model);
    }
    if (description) {
      writeComment("  " + localize("description") + ": "  + description);
    }
  }

  // dump tool information
  if (properties.writeTools) {
    var zRanges = {};
    if (is3D()) {
      var numberOfSections = getNumberOfSections();
      for (var i = 0; i < numberOfSections; ++i) {
        var section = getSection(i);
        var zRange = section.getGlobalZRange();
        var tool = section.getTool();
        if (zRanges[tool.number]) {
          zRanges[tool.number].expandToRange(zRange);
        } else {
          zRanges[tool.number] = zRange;
        }
      }
    }

    var tools = getToolTable();
    if (tools.getNumberOfTools() > 0) {
      for (var i = 0; i < tools.getNumberOfTools(); ++i) {
        var tool = tools.getTool(i);
        var comment = "T" + toolFormat.format(tool.number) + "  " +
          "D=" + xyzFormat.format(tool.diameter) + " " +
          localize("CR") + "=" + xyzFormat.format(tool.cornerRadius);
        if ((tool.taperAngle > 0) && (tool.taperAngle < Math.PI)) {
          comment += " " + localize("TAPER") + "=" + taperFormat.format(tool.taperAngle) + localize("deg");
        }
        if (zRanges[tool.number]) {
          comment += " - " + localize("ZMIN") + "=" + xyzFormat.format(zRanges[tool.number].getMinimum());
        }
        comment += " - " + getToolTypeName(tool.type);
        writeComment(comment);
      }
    }
  }
}

function onComment(message) {
  writeComment(message);
}

/** Force output of X, Y, and Z. */
function forceXYZ() {
  xOutput.reset();
  yOutput.reset();
  zOutput.reset();
}

/** Force output of X, Y, Z, and F on next output. */
function forceAny() {
  forceXYZ();
  feedOutput.reset();
}

function onSection() {
  setTranslation(currentSection.workOrigin);
  setRotation(currentSection.workPlane);
  
  var insertToolCall = isFirstSection() || (tool.number != getPreviousSection().getTool().number);
  
  var retracted = false; // specifies that the tool has been retracted to the safe plane

  if (hasParameter("operation-comment")) {
    var comment = getParameter("operation-comment");
    if (comment) {
      writeComment(comment);
    }
  }

  if (insertToolCall) {
    retracted = true;
    onCommand(COMMAND_COOLANT_OFF);
  
    if (tool.number > numberOfToolSlots) {
      warning(localize("Tool number exceeds maximum value."));
    }

    writeln("Werkzeug " + toolFormat.format(tool.number) + ",0,0,1;");
    // writeln("Fdurch " + xyzFormat.format(tool.diameter) + ",0,2;");
    
    if (tool.comment) {
      writeComment(tool.comment);
    }
    var showToolZMin = false;
    if (showToolZMin) {
      if (is3D()) {
        var numberOfSections = getNumberOfSections();
        var zRange = currentSection.getGlobalZRange();
        var number = tool.number;
        for (var i = currentSection.getId() + 1; i < numberOfSections; ++i) {
          var section = getSection(i);
          if (section.getTool().number != number) {
            break;
          }
          zRange.expandToRange(section.getGlobalZRange());
        }
        writeComment(localize("ZMIN") + "=" + zRange.getMinimum());
      }
    }
  }
  
  if (insertToolCall ||
      isFirstSection() ||
      (rpmFormat.areDifferent(tool.spindleRPM, getPreviousSection().getTool().spindleRPM)) ||
      (tool.clockwise != getPreviousSection().getTool().clockwise)) {
    if (tool.spindleRPM < 1) {
      error(localize("Spindle speed out of range."));
      return;
    }
    if (tool.spindleRPM > 99999) {
      warning(localize("Spindle speed exceeds maximum value."));
    }
    writeln("Drehzahl 1," + rpmFormat.format(tool.spindleRPM) + ",0,0," + rpmFormat.format(tool.spindleRPM) + ";");
    if (!tool.clockwise) {
      error(localize("Spindle direction not supported."));
      return;
    }
  }

  // wcs
  if (currentSection.workOffset != 0) {
    // warningOnce(localize("Work offset is not supported."), WARNING_WORK_OFFSET);
    writeln("MKoord " + currentSection.workOffset + ",0;");
  }

  forceXYZ();

  if (tool.coolant != COOLANT_OFF) {
    warningOnce(localize("Coolant not supported."), WARNING_COOLANT);
  }
  // Absaugung [0-1], [0-3]
  
  // Glaettung se, s, gf, mw;
  
  forceAny();

  var initialPosition = getFramePosition(currentSection.getInitialPosition());
  if (!retracted) {
    if (getCurrentPosition().z < initialPosition.z) {
      writeln("Axyz 1," + xOutput.format(getCurrentPosition().x) + "," + yOutput.format(getCurrentPosition().y) + "," + zOutput.format(initialPosition.z) + ",0,0;");
    }
  }

  writeln("Axyz 1," + xOutput.format(initialPosition.x) + "," + yOutput.format(initialPosition.y) + "," + zOutput.format(initialPosition.z) + ",0,0;");
}

function onRadiusCompensation() {
  if (radiusCompensation != RADIUS_COMPENSATION_OFF) {
    error(localize("Radius compensation mode not supported."));
  }
}

function onDwell(seconds) {
  writeln("Verweile " + secFormat.format(seconds) + ",0,0,0,0,0,0;");
}

function onSpindleSpeed(spindleSpeed) {
  writeln("Drehzahl 1," + rpmFormat.format(spindleSpeed) + ",0,0," + rpmFormat.format(spindleSpeed) + ";");
  if (!tool.clockwise) {
    error(localize("Spindle direction not supported."));
    return;
  }
  writeBlock(sOutput.format());
}

function onRapid(_x, _y, _z) {
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  writeln("Axyz 1," + x + "," + y + "," + z + ",0,0;");
  feedOutput.reset();
}

function onLinear(_x, _y, _z, feed) {

  // TAG: writeln("Fkomp md,0,0,0,0;"); // md 0 disabled, 1 left, 2 right

  var f = feedOutput.format(feed);
  if (f) {
    writeln("Vorschub " + f + "," + f + "," + f + "," + f + ";");
  }
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  writeln("Axyz 0," + x + "," + y + "," + z + ",0,0;");
}

function onCircular(clockwise, cx, cy, cz, x, y, z, feed) {
  var f = feedOutput.format(feed);
  if (f) {
    writeln("Vorschub " + f + "," + f + "," + f + "," + f + ";");
  }

  if (isHelical() || (getCircularPlane() != PLANE_XY)) {
    var t = tolerance;
    if (hasParameter("operation:tolerance")) {
      t = getParameter("operation:tolerance");
    }
    linearize(t);
    return;
  }
  
  var start = getCurrentPosition();
  var startAngle = Math.atan2(start.y - cy, start.x - cx);
  var endAngle = Math.atan2(y - cy, x - cx);

  writeln(
    "Kreis " +
    xyzFormat.format(2 * getCircularRadius()) + "," +
    "0," + // hs
    "0," + // hl
    (clockwise ? -360 : 0) + "," +
    angleFormat.format(startAngle) + "," + // begin angle
    angleFormat.format(endAngle) + "," + // end angle
    "0," + // do not connect start/end
    "0," + // center
    "2," + // fk
    "1," + // yf
    xyzFormat.format(getHelicalPitch()) + ";" // zb
  );
}

function onCommand(command) {
  if (command != COMMAND_COOLANT_OFF) {
    error(localize("Unsupported command"));
  }
}

function onSectionEnd() {
  forceAny();
}

function onClose() {
  onCommand(COMMAND_COOLANT_OFF);

  // writeln("Referenz 1,1,1,1,1,1;");

  if (!machineConfiguration.hasHomePositionX() && !machineConfiguration.hasHomePositionY()) {
  } else {
    var homeX;
    if (machineConfiguration.hasHomePositionX()) {
      homeX = "X" + xyzFormat.format(machineConfiguration.getHomePositionX());
    }
    var homeY;
    if (machineConfiguration.hasHomePositionY()) {
      homeY = "Y" + xyzFormat.format(machineConfiguration.getHomePositionY());
    }
  }
}

