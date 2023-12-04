using Toybox.Activity as Activity;
using Toybox.Application as App;
using Toybox.Application.Storage as Storage;
using Toybox.WatchUi as Ui;
using Toybox.Graphics as Graphics;
using Toybox.System as System;
using Toybox.Time as Time;
using Toybox.Timer as Timer;
using Toybox.FitContributor as FitContributor;
using Toybox.UserProfile as UserProfile;

enum {
    TYPE_DURATION,
    TYPE_DISTANCE,
    TYPE_SPEED,
    TYPE_HR,
    TYPE_STEPS,
    TYPE_ELEVATION,
    TYPE_ASCENT,
}

enum {
    STEPS_FIELD_ID = 0,
    STEPS_LAP_FIELD_ID = 1,
}

class HikeField extends App.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        var view = new HikeView();
        return [ view ];
    }
}

class InfoField {
    hidden var FONT_JUSTIFY = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

    var x = 0;
    var y_header = 0;
    var y_value = 0;

    function initialize(x_pos, y_header_pos, y_value_pos) {
        x = x_pos;
        y_header = y_header_pos;
        y_value = y_value_pos;
    }

    function drawHeader(dc, color, style, text) {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y_header, style, text, FONT_JUSTIFY);
    }

    function drawValue(dc, color, style, text) {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y_value, style, text, FONT_JUSTIFY);
    }
}

class HikeView extends Ui.DataField {
    hidden var ready = false;

    hidden var FONT_JUSTIFY = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
    hidden var FONT_HEADER_STR = Graphics.FONT_XTINY;
    hidden var FONT_HEADER_VAL = Graphics.FONT_XTINY;
    hidden var FONT_VALUE = Graphics.FONT_NUMBER_MILD;
    hidden var NUM_INFO_FIELDS = 7;

    var totalStepsField;
    var lapStepsField;

    hidden var kmOrMileInMeters = 1000;
    hidden var mOrFeetsInMeter = 1;
    hidden var is24Hour = true;

    //colors
    hidden var distanceUnits = System.UNIT_METRIC;
    hidden var elevationUnits = System.UNIT_METRIC;
    hidden var textColor = Graphics.COLOR_BLACK;
    hidden var inverseTextColor = Graphics.COLOR_WHITE;
    hidden var backgroundColor = Graphics.COLOR_WHITE;
    hidden var inverseBackgroundColor = Graphics.COLOR_BLACK;
    hidden var inactiveGpsBackground = Graphics.COLOR_LT_GRAY;
    hidden var batteryBackground = Graphics.COLOR_WHITE;
    hidden var batteryColor1 = Graphics.COLOR_GREEN;
    hidden var hrColor = Graphics.COLOR_RED;
    hidden var headerColor = Graphics.COLOR_DK_GRAY;

    //strings
    hidden var durationHeader, distanceHeader, hrHeader, stepsHeader, speedHeader, paceHeader, elevationHeader;
    hidden var timeVal, distVal, distToNextPointVal, notificationVal, paceVal, avgPaceVal;

    //data
    hidden var elapsedTime= 0;
    hidden var distance = 0;
    hidden var distanceToNextPoint = 0;
    hidden var cadence = 0;
    hidden var hr = 0;
    hidden var hrZone = 0;
    hidden var elevation = 0;
    hidden var maxelevation = -65536;
    hidden var speed = 0;
    hidden var avgSpeed = 0;
    hidden var pace = 0;
    hidden var avgPace = 0;
    hidden var ascent = 0;
    hidden var descent = 0;
    hidden var grade = 0;
    hidden var pressure = 0;
    hidden var gpsSignal = 0;
    hidden var stepPrev = 0;
    hidden var stepCount = 0;
    hidden var stepPrevLap = 0;
    hidden var stepsPerLap = [];
    hidden var startTime = [];
    hidden var stepsAddedToField = 0;

    hidden var hasDistanceToNextPoint = false;
    hidden var hasAmbientPressure = false;

    hidden var checkStorage = false;

    hidden var phoneConnected = false;
    hidden var notificationCount = 0;

    hidden var hasBackgroundColorOption = false;

    hidden var doUpdates = 0;
    hidden var activityRunning = false;

    hidden var dcWidth = 0;
    hidden var dcHeight = 0;
    hidden var centerX = 0;

    hidden var infoFields = new [NUM_INFO_FIELDS];
    hidden var topBarHeight;
    hidden var bottomBarHeight;
    hidden var firstRowOffset;
    hidden var secondRowOffset;
    hidden var bottomOffset;

    hidden var settingsUnlockCode = Application.getApp().getProperty("unlockCode");
    hidden var settingsShowCadence = Application.getApp().getProperty("showCadence");
    hidden var settingsShowHR = Application.getApp().getProperty("showHR");
    hidden var settingsShowHRZone = Application.getApp().getProperty("showHRZone");
    hidden var settingsMaxElevation = Application.getApp().getProperty("showMaxElevation");
    hidden var settingsNotification = Application.getApp().getProperty("showNotification");
    hidden var settingsGrade = Application.getApp().getProperty("showGrade");
    hidden var settingsGradePressure = Application.getApp().getProperty("showGradePressure");
    hidden var settingsDistanceToNextPoint = Application.getApp().getProperty("showDistanceToNextPoint");
    hidden var settingsShowPace = Application.getApp().getProperty("showPace");
    hidden var settingsShowAvgSpeed = Application.getApp().getProperty("showAvgSpeed");
    hidden var settingsAvaiable = false;

    hidden var hrZoneInfo;

    hidden var gradeBuffer = new[10];
    hidden var gradeBufferPos = 0;
    hidden var gradeBufferSkip = 0;
    hidden var gradePrevData = 0.0;
    hidden var gradePrevDistance = 0.0;
    hidden var gradeFirst = true;


    function initialize() {
        DataField.initialize();

        totalStepsField = createField(
            Ui.loadResource(Rez.Strings.steps_label),
            STEPS_FIELD_ID,
            FitContributor.DATA_TYPE_UINT32,
            {:mesgType=>FitContributor.MESG_TYPE_SESSION , :units=>Ui.loadResource(Rez.Strings.steps_unit)}
        );

        lapStepsField = createField(
            Ui.loadResource(Rez.Strings.steps_label),
            STEPS_LAP_FIELD_ID,
            FitContributor.DATA_TYPE_UINT32,
            {:mesgType=>FitContributor.MESG_TYPE_LAP , :units=>Ui.loadResource(Rez.Strings.steps_unit)}
        );

        Application.getApp().setProperty("uuid", System.getDeviceSettings().uniqueIdentifier);

        settingsAvaiable = true;

        hrZoneInfo = UserProfile.getHeartRateZones(UserProfile.HR_ZONE_SPORT_GENERIC);

        for (var i = 0; i < 10; i++){
            gradeBuffer[i] = null;
        }

        if (Activity.Info has :distanceToNextPoint) {
            hasDistanceToNextPoint = true;
        }

        if (Activity.Info has :ambientPressure) {
            hasAmbientPressure = true;
        }
    }

    function compute(info) {
        elapsedTime = info.timerTime != null ? info.timerTime : 0;

        var hours = null;
        var minutes = elapsedTime / 1000 / 60;
        var seconds = elapsedTime / 1000 % 60;

        if (minutes >= 60) {
            hours = minutes / 60;
            minutes = minutes % 60;
        }

        if (hours == null) {
            timeVal = minutes.format("%d") + ":" + seconds.format("%02d");
        } else {
            timeVal = hours.format("%d") + ":" + minutes.format("%02d");
        }

        hr = info.currentHeartRate != null ? info.currentHeartRate : 0;
        distance = info.elapsedDistance != null ? info.elapsedDistance : 0;
        if (hasDistanceToNextPoint) {
            distanceToNextPoint = info.distanceToNextPoint;
        }

        var distanceKmOrMiles = distance / kmOrMileInMeters;
        if (distanceKmOrMiles < 100) {
            distVal = distanceKmOrMiles.format("%.2f");
        } else {
            distVal = distanceKmOrMiles.format("%.1f");
        }

        if (distanceToNextPoint != null) {
            distanceKmOrMiles = distanceToNextPoint / kmOrMileInMeters;
            if (distanceKmOrMiles < 100) {
                distToNextPointVal = distanceKmOrMiles.format("%.2f");
            } else {
                distToNextPointVal = distanceKmOrMiles.format("%.1f");
            }
        }

        gpsSignal = info.currentLocationAccuracy != null ? info.currentLocationAccuracy : 0;
        cadence = info.currentCadence != null ? info.currentCadence : 0;
        speed = info.currentSpeed != null ? info.currentSpeed : 0;
        avgSpeed = info.averageSpeed != null ? info.averageSpeed : 0;

        speed = speed * 3600 / kmOrMileInMeters;
        if (speed >= 1) {
            pace = (3600 / speed).toLong();
            paceVal = (pace / 60).format("%d") + ":" + (pace % 60).format("%02d");
        } else {
            paceVal = "--:--";
        }

        avgSpeed = avgSpeed * 3600 / kmOrMileInMeters;
        if (avgSpeed >= 1) {
            avgPace = (3600 / avgSpeed).toLong();
            avgPaceVal = (avgPace / 60).format("%d") + ":" + (avgPace % 60).format("%02d");
        } else {
            avgPaceVal = "--:--";
        }

        ascent = info.totalAscent != null ? (info.totalAscent * mOrFeetsInMeter) : 0;
        descent = info.totalDescent != null ? (info.totalDescent * mOrFeetsInMeter)  : 0;
        elevation = info.altitude != null ? info.altitude : 0;
        if (hasAmbientPressure) {
            pressure = info.ambientPressure != null ? info.ambientPressure : 0;
        }

        hrZone = 0;

        for (var i = hrZoneInfo.size(); i > 0; i--) {
            if (hr > hrZoneInfo[i - 1]) {
                hrZone = i;
                break;
            }
        }

        if (hr == 0) {
            hrZone = 0;
        } else if (hrZone == 6) {
            hrZone = 5;
        } else {
            var diff;
            if (hrZone == 0) {
                diff = hrZoneInfo[hrZone] / 2;
                diff = (hr.toFloat() - hrZoneInfo[hrZone] / 2) / diff;
            } else {
                diff = hrZoneInfo[hrZone] - hrZoneInfo[hrZone - 1];
                diff = (hr.toFloat() - hrZoneInfo[hrZone - 1]) / diff;
            }
            hrZone = hrZone + diff;
        }

        if (stepsAddedToField < stepsPerLap.size() * 2) {
            if (stepsAddedToField & 0x1) {
                lapStepsField.setData(stepsPerLap[stepsAddedToField / 2]);
            }
            stepsAddedToField++;
        }

        if (activityRunning) {
            if (checkStorage && Activity.getActivityInfo().startTime != null) {
                checkStorage = false;
                var savedStartTime = null;
                startTime = Activity.getActivityInfo().startTime;
                savedStartTime = Storage.getValue("startTime");
                if (savedStartTime != null && startTime != null && startTime.value() == savedStartTime) {
                    stepCount = Storage.getValue("totalSteps");
                    stepsPerLap = Storage.getValue("stepsPerLap");
                    if (stepsPerLap.size() > 0) {
                        stepPrevLap = stepsPerLap[stepsPerLap.size() - 1];
                    }
                }
            }
            var stepCur = ActivityMonitor.getInfo().steps;
            if (stepCur < stepPrev) {
                stepCount = stepCount + stepCur;
                stepPrev = stepCur;
            } else {
                stepCount = stepCount + stepCur - stepPrev;
                stepPrev = stepCur;
            }
        }

        var mySettings = System.getDeviceSettings();
        phoneConnected = mySettings.phoneConnected;
        if (phoneConnected) {
            notificationCount = mySettings.notificationCount;
        }

        if (settingsAvaiable && settingsGrade && (distance > 0)) {
            if (gradeFirst) {
                if (!settingsGradePressure) {
                    gradePrevData = elevation;
                } else {
                    gradePrevData = pressure;
                }
                gradePrevDistance = distance;
                gradeFirst = false;
            }
            var change = false;
            gradeBufferSkip++;
            if (gradeBufferSkip == 5) {
                gradeBufferSkip = 0;
                change = true;
            }

            if (change) {
                if (distance != gradePrevDistance) {
                    if (!settingsGradePressure || !hasAmbientPressure) {
                        gradeBuffer[gradeBufferPos] = (elevation - gradePrevData) / (distance - gradePrevDistance);
                        gradePrevData = elevation;
                    } else {
                        gradeBuffer[gradeBufferPos] = (8434.15 * (gradePrevData - pressure) / pressure) / (distance - gradePrevDistance);
                        gradePrevData = pressure;
                    }
                    gradePrevDistance = distance;
                    gradeBufferPos++;

                    if (gradeBufferPos == 10) {
                        gradeBufferPos = 0;
                    }

                    var gradeSum = 0.0;
                    var gradeNum = 0;

                    for (var i = 0; i < 10; i++) {
                        if (gradeBuffer[i] != null) {
                            gradeNum++;
                            gradeSum += gradeBuffer[i];
                        }
                    }
                    grade = 100 * gradeSum / gradeNum;
                }
            }
        }

        elevation *= mOrFeetsInMeter;
        if (elevation > maxelevation) {
            maxelevation = elevation;
        }

        ready = true;
    }

    function onLayout(dc) {
        distanceUnits = System.getDeviceSettings().distanceUnits;
        if (distanceUnits != System.UNIT_METRIC) {
            kmOrMileInMeters = 1609.344;
        }

        elevationUnits = System.getDeviceSettings().elevationUnits;
        if (elevationUnits != System.UNIT_METRIC) {
            mOrFeetsInMeter = 3.2808399;
        }
        is24Hour = System.getDeviceSettings().is24Hour;

        hrHeader = Ui.loadResource(Rez.Strings.hr);
        distanceHeader = Ui.loadResource(Rez.Strings.distance);
        durationHeader = Ui.loadResource(Rez.Strings.duration);
        stepsHeader = Ui.loadResource(Rez.Strings.steps);
        speedHeader = Ui.loadResource(Rez.Strings.speed);
        paceHeader = Ui.loadResource(Rez.Strings.pace);
        elevationHeader = Ui.loadResource(Rez.Strings.elevation);

        hasBackgroundColorOption = (self has :getBackgroundColor);

        dcHeight = dc.getHeight();
        dcWidth = dc.getWidth();
        centerX = dcWidth / 2;
        topBarHeight = dcHeight / 8;
        bottomBarHeight = dcHeight / 6;
        firstRowOffset = dcHeight / 24;
        secondRowOffset = dcHeight / 6;
        bottomOffset = dcHeight / 8;

        // Layout positions for the seven grid items we'll be displaying
        // Each grid item has a header (small font) and a value (large font)
        // In some situations, the header may contain a title; in others, this
        // may be an auxiliary value
        infoFields[0] = new InfoField(dcWidth * 2 / 7,
                                  topBarHeight + firstRowOffset,
                                  topBarHeight + secondRowOffset);

        infoFields[1] = new InfoField(dcWidth - dcWidth * 2 / 7,
                                  topBarHeight + firstRowOffset,
                                  topBarHeight + secondRowOffset);

        infoFields[2] = new InfoField(dcWidth * 2 / 11,
                                  topBarHeight + (dcHeight - topBarHeight - bottomBarHeight) / 3 + firstRowOffset,
                                  topBarHeight + (dcHeight - topBarHeight - bottomBarHeight) / 3 + secondRowOffset);

        infoFields[3] = new InfoField(dcWidth - dcWidth * 2 / 11,
                                  topBarHeight + (dcHeight - topBarHeight - bottomBarHeight) / 3 + firstRowOffset,
                                  topBarHeight + (dcHeight - topBarHeight - bottomBarHeight) / 3 + secondRowOffset);

        infoFields[4] = new InfoField(dcWidth / 2,
                                  topBarHeight + (dcHeight - topBarHeight - bottomBarHeight) / 3 + firstRowOffset,
                                  topBarHeight + (dcHeight - topBarHeight - bottomBarHeight) / 3 + secondRowOffset);

        infoFields[5] = new InfoField(dcWidth / 4,
                                  topBarHeight + (dcHeight - topBarHeight - bottomBarHeight) / 3 * 2 + firstRowOffset,
                                  topBarHeight + (dcHeight - topBarHeight - bottomBarHeight) / 3 * 2 + secondRowOffset);

        infoFields[6] = new InfoField(dcWidth - dcWidth / 4,
                                  topBarHeight + (dcHeight - topBarHeight - bottomBarHeight) / 3 * 2 + firstRowOffset,
                                  topBarHeight + (dcHeight - topBarHeight - bottomBarHeight) / 3 * 2 + secondRowOffset);
    }

    function onShow() {
        doUpdates = true;
    }

    function onHide() {
        doUpdates = false;
    }

    function onUpdate(dc) {
        if(doUpdates == false) {
            return;
        }

        dc.clear();

        if (!ready) {
            return;
        }

        if (hasBackgroundColorOption) {
            if (backgroundColor != getBackgroundColor()) {
                backgroundColor = getBackgroundColor();
                if (backgroundColor == Graphics.COLOR_BLACK) {
                    textColor = Graphics.COLOR_WHITE;
                    batteryColor1 = Graphics.COLOR_BLUE;
                    hrColor = Graphics.COLOR_BLUE;
                    headerColor = Graphics.COLOR_LT_GRAY;
                } else {
                    textColor = Graphics.COLOR_BLACK;
                    batteryColor1 = Graphics.COLOR_GREEN;
                    hrColor = Graphics.COLOR_RED;
                    headerColor = Graphics.COLOR_DK_GRAY;
                }
            }
        }

        dc.setColor(backgroundColor, backgroundColor);
        dc.fillRectangle(0, 0, dcWidth, dcHeight);

        //time start
        var clockTime = System.getClockTime();
        var time;
        if (is24Hour) {
            time = Lang.format("$1$:$2$", [clockTime.hour, clockTime.min.format("%.2d")]);
        } else {
            time = Lang.format("$1$:$2$", [computeHour(clockTime.hour), clockTime.min.format("%.2d")]);
            time += (clockTime.hour < 12) ? " am" : " pm";
        }
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillRectangle(0, 0, dcWidth, topBarHeight);
        dc.setColor(inverseTextColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, topBarHeight / 2, Graphics.FONT_MEDIUM, time, FONT_JUSTIFY);
        //time end

        //battery and gps start
        dc.setColor(inverseBackgroundColor, inverseBackgroundColor);
        dc.fillRectangle(0, dcHeight - bottomBarHeight, dcWidth, bottomBarHeight);

        drawBattery(System.getSystemStats().battery, dc, centerX - 50, dcHeight - bottomOffset, 28, 17); //todo

        var xStart = centerX + 24;
        var yStart = dcHeight - bottomOffset - 5;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawRectangle(xStart - 1, yStart + 11, 8, 10);
        if (gpsSignal < 2) {
            dc.setColor(inactiveGpsBackground, Graphics.COLOR_TRANSPARENT);
        } else {
            dc.setColor(batteryColor1, Graphics.COLOR_TRANSPARENT);
        }
        dc.fillRectangle(xStart, yStart + 12, 6, 8);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawRectangle(xStart + 6, yStart + 7, 8, 14);
        if (gpsSignal < 3) {
            dc.setColor(inactiveGpsBackground, Graphics.COLOR_TRANSPARENT);
        } else {
            dc.setColor(batteryColor1, Graphics.COLOR_TRANSPARENT);
        }
        dc.fillRectangle(xStart + 7, yStart + 8, 6, 12);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawRectangle(xStart + 13, yStart + 3, 8, 18);
        if (gpsSignal < 4) {
            dc.setColor(inactiveGpsBackground, Graphics.COLOR_TRANSPARENT);
        } else {
            dc.setColor(batteryColor1, Graphics.COLOR_TRANSPARENT);
        }
        dc.fillRectangle(xStart + 14, yStart + 4, 6, 16);
        //battery and gps end

        //notification start
        if (!(settingsAvaiable && !settingsNotification)) {
            if (phoneConnected) {
                notificationVal = notificationCount.format("%d");
            } else {
                notificationVal = "-";
            }

            dc.setColor(inverseTextColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centerX, dcHeight - bottomOffset + 5, Graphics.FONT_MEDIUM, notificationVal, FONT_JUSTIFY);
        }
        //notification end

        //grid start
        dc.setPenWidth(2);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(0, topBarHeight, dcWidth, topBarHeight);
        dc.drawLine(0, dcHeight - bottomBarHeight, dcWidth, dcHeight - bottomBarHeight);

        // Vertical line that runs down the center of the screen
        dc.drawLine(centerX, topBarHeight, centerX, dcHeight - bottomBarHeight - 1);

        // Horizontal line 1
        dc.drawLine(0, infoFields[2].y_header - firstRowOffset, dcWidth, infoFields[2].y_header - firstRowOffset);

        // Horizontal line 2
        dc.drawLine(0, infoFields[5].y_header - firstRowOffset, dcWidth, infoFields[5].y_header - firstRowOffset);

        if (!(settingsAvaiable && !settingsShowHR)) {
            dc.setColor(backgroundColor, backgroundColor);
            dc.fillCircle(centerX, topBarHeight + (dcHeight - topBarHeight - bottomBarHeight) / 2, dcHeight / 8);
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(centerX, topBarHeight + (dcHeight - topBarHeight - bottomBarHeight) / 2, dcHeight / 8 + 1);
        }

        dc.setPenWidth(1);
        //grid end

        drawInfo(dc, infoFields[0], TYPE_DURATION);
        drawInfo(dc, infoFields[1], TYPE_DISTANCE);
        drawInfo(dc, infoFields[2], TYPE_SPEED);
        drawInfo(dc, infoFields[3], TYPE_STEPS);
        drawInfo(dc, infoFields[4], TYPE_HR);
        drawInfo(dc, infoFields[5], TYPE_ELEVATION);
        drawInfo(dc, infoFields[6], TYPE_ASCENT);
    }

    function onTimerStart() {
        activityRunning = true;
        stepPrev = ActivityMonitor.getInfo().steps;
        checkStorage = true;
    }

    function onTimerResume() {
        activityRunning = true;
        stepPrev = ActivityMonitor.getInfo().steps;
    }

    function onTimerPause() {
        activityRunning = false;
    }

    function onTimerStop() {
        var sum = 0;
        Storage.setValue("startTime", Activity.getActivityInfo().startTime.value());
        Storage.setValue("totalSteps", stepCount);
        Storage.setValue("stepsPerLap", stepsPerLap);
        activityRunning = false;
        totalStepsField.setData(stepCount);
        for (var i = 0; i < stepsPerLap.size(); i++) {
            sum += stepsPerLap[i];
        }
        lapStepsField.setData(stepCount - sum);
    }

    function onTimerLap() {
        stepsPerLap.add(stepCount - stepPrevLap);
        stepPrevLap = stepCount;
    }

    function drawInfo(dc, field, type) {
        var text_line_1 = "";
        var text_line_2 = "";

        var headerStyle = FONT_HEADER_STR;
        var valColor = textColor;

        if (type == TYPE_DURATION) {
            text_line_1 = durationHeader;
            text_line_2 = timeVal;
        } else if (type == TYPE_DISTANCE) {
            if (settingsAvaiable && settingsDistanceToNextPoint && (distanceToNextPoint != null)) {
                text_line_1 = distToNextPointVal;
            } else {
                text_line_1 = distanceHeader;
            }
            text_line_2 = distVal;
        } else if (type == TYPE_SPEED) {
            if (!(settingsAvaiable && !settingsShowCadence)) {
                headerStyle = FONT_HEADER_VAL;
                text_line_1 = cadence;
            } else if (settingsAvaiable && settingsShowAvgSpeed) {
                if (settingsAvaiable && settingsShowPace) {
                    text_line_1 = avgPaceVal;
                } else {
                    text_line_1 = avgSpeed.format("%.1f");
                }
            } else {
                if (settingsAvaiable && settingsShowPace) {
                    text_line_1 = paceHeader;
                } else {
                    text_line_1 = speedHeader;
                }
            }
            if (settingsAvaiable && settingsShowPace) {
                text_line_2 = paceVal;
            } else {
                text_line_2 = speed.format("%.1f");
            }
        } else if (type == TYPE_HR) {
            if (!(settingsAvaiable && !settingsShowHR)) {
                valColor = hrColor;
                text_line_1 = hrHeader;
                if (settingsAvaiable && settingsShowHRZone) {
                    text_line_2 = hrZone.format("%.1f");
                } else {
                    text_line_2 = hr;
                }
            } else {
                return;
            }
        } else if (type == TYPE_STEPS) {
            text_line_1 = stepsHeader;
            text_line_2 = stepCount;
        } else if (type == TYPE_ELEVATION) {
            if (!(settingsAvaiable && !settingsMaxElevation)) {
                headerStyle = FONT_HEADER_VAL;
                text_line_1 = maxelevation.format("%.0f");
            } else {
                text_line_1 = elevationHeader;
            }
            text_line_2 = elevation.format("%.0f");
        } else if (type == TYPE_ASCENT) {
            headerStyle = FONT_HEADER_VAL;
            if (settingsAvaiable && settingsGrade) {
                text_line_1 = grade.format("%.1f");
            } else {
                text_line_1 = descent.format("%.0f");
            }
            text_line_2 = ascent.format("%.0f");
        } else {
            return;
        }

        field.drawHeader(dc, headerColor, headerStyle, text_line_1);
        field.drawValue(dc, valColor, FONT_VALUE, text_line_2);
    }

    function drawBattery(battery, dc, xStart, yStart, width, height) {
        dc.setColor(batteryBackground, inactiveGpsBackground);
        dc.fillRectangle(xStart, yStart, width, height);
        if (battery < 10) {
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(xStart+3 + width / 2, yStart + 7, FONT_HEADER_STR, format("$1$%", [battery.format("%d")]), FONT_JUSTIFY);
        }

        if (battery < 10) {
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        } else if (battery < 30) {
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
        } else {
            dc.setColor(batteryColor1, Graphics.COLOR_TRANSPARENT);
        }
        dc.fillRectangle(xStart + 1, yStart + 1, (width-2) * battery / 100, height - 2);

        dc.setColor(batteryBackground, batteryBackground);
        dc.fillRectangle(xStart + width - 1, yStart + 3, 4, height - 6);
    }

    function computeHour(hour) {
        if (hour < 1) {
            return hour + 12;
        }
        if (hour >  12) {
            return hour - 12;
        }
        return hour;
    }
}
