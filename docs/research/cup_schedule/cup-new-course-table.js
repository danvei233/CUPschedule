/**
 * Created by wx on 17-6-5.
 */
var courseTableDataList = [];
var weekIndices = [];
var lessonIds = [];
var lessons = {};
var currentWeek = '';
var currentBizTypeId = '';
var bgColors = ['rgba(56, 200, 180, 0.2)', 'rgba(121, 150, 202, 0.2)', 'rgba(169, 206, 149, 0.2)', 'rgba(111, 176, 243, 0.2)', 'rgba(210, 161, 242, 0.2)', 'rgba(218, 196, 165, 0.2)',
  'rgba(244, 144, 96, 0.2)', 'rgba(255, 117, 117, 0.2)', 'rgba(253, 171, 154, 0.2)', 'rgba(154, 166, 189, 0.2)', 'rgba(213, 208, 208, 0.2)', 'rgba(240, 200, 109, 0.2)']
var lessonColors = {};
var commonUnits = [];
var getDrawTableData = function (ids, bizTypeId, semesterId, type, personId) {
  courseTableDataList = [];
  weekIndices = [];
  currentWeek = '';
  lessonIds = [];
  currentBizTypeId = bizTypeId;

  $("#weeks").selectize({});
  var semesterName = '';

  if (ids != null) {
    if (type === 'lesson') {
      var tableId = ids.join('-');
      var $oneCourseTalbe = $('<div class="paging export-content" style="padding-bottom: 30px;" id="' + tableId + '-div"></div>');
      $('.table-container').append($oneCourseTalbe);
    }else if((type === 'student'|| type ==='headTeacher') && personId) {
       var newIds = ids.sort(function(a, b){
            return a - b;
       });
      ids = [ids[0]]; //一个学生可能有多个学号，但是只请求一次
      var $oneCourseTalbe = $('<div class="paging export-content" style="padding-bottom: 30px;" id="' + newIds.join('-') + '-div"></div>');
      $('.table-container').append($oneCourseTalbe);
    } else {
      $.each(ids, function (index, item) {
        item = (item).toString().indexOf(',') !== -1 ? (item).toString().replaceAll(',', '-') : item;
        var $oneCourseTalbe = $('<div class="paging export-content" style="padding-bottom: 30px;" id="' + item + '-div"></div>');
        $('.table-container').append($oneCourseTalbe);
      });
    }

  }

  $('#print').click(function () {
    PrintHelper.print();
  });

  $.ajax({
    async: false,
    url: window.CONTEXT_PATH + '/ws/semester/get/' + semesterId,
    success: function (res) {
      semesterName = res.nameZh;
    }
  });
  var arr1 = [];
  var arr2 = [];
  var arr3 = [];
  var arr4 = [];
  var arr5 = [];

  if(ids != null){
    for (var i = 0; i < ids.length; i++) {
      ids[i] ? arr1.push(ids[i]) : '';
      ids[++i] ? arr2.push(ids[i]) : '';
      ids[++i] ? arr3.push(ids[i]) : '';
      ids[++i] ? arr4.push(ids[i]) : '';
      ids[++i] ? arr5.push(ids[i]) : '';
    }
  }

  function updateProgress(percentage) {

    $(".semester-container").html(semesterName);

    var width = (percentage / ids.length).toFixed(2) * 100;
    $('.progress .progress-bar').css('width', width + '%').html(percentage + '/' + ids.length);

    if (percentage === ids.length) {
      $("#progress-bar-modal").modal('hide');
    }
  }

  var i1 = 0;
  var i2 = 0;
  var i3 = 0;
  var i4 = 0;
  var i5 = 0;
  var baseUrl = '';
  var getDataUrl = '';
  if (!bizTypeId && type === 'teacher') { // 教师端课表
    baseUrl = '/for-teacher/course-table/semester/' + semesterId + '/print-data/';
    getDataUrl = '/for-teacher/course-table/get-data';
  } else if (type === 'student' && personId) { // 学生端学生课表
    baseUrl = '/for-std/course-table/semester/' + semesterId + '/print-data';
    getDataUrl = '/for-std/course-table/get-data';
  } else if(type === 'stdAdminclass'){ // 学生端班级课表
    baseUrl = '/for-std/adminclass-course-table/print-data';
    getDataUrl = '/for-std/adminclass-course-table/get-data?'+ 'studentId='+personId;
  } else if(type === 'parent'){ //家长端
    baseUrl = '/for-parent/course-table/semester/' + semesterId + '/print-data/';
    getDataUrl = '/for-parent/course-table/get-data';
  } else if(type === 'teacherAdminclass'){
    baseUrl = '/for-teacher/adminclass-course-table/semester/' + semesterId + '/print-data/';
    getDataUrl = '/for-teacher/adminclass-course-table/get-data';
  } else if(type === 'studentAdminclass'){
    baseUrl = '/for-student/adminclass-course-table/semester/' + semesterId + '/print-data/';
    getDataUrl = '/for-student/adminclass-course-table/get-data';
  } else if(type === 'teacherRoom'){ //教师端教室课表
    baseUrl = '/for-teacher/room-course-table/semester/' + semesterId + '/print-data/';
    getDataUrl = '/for-teacher/room-course-table/get-data';
  } else if(type === 'studentRoom'){ //教师端教室课表
    baseUrl = '/for-std/room-course-table/semester/' + semesterId + '/print-data/';
    getDataUrl = '/for-std/room-course-table/get-data';
  } else if(type ==='headTeacher'){
    baseUrl = '/for-std/course-table/semester/' + semesterId + '/print-data';
    getDataUrl = '/for-teacher/select/std-tutor-ware/get-data';
  }
  else {
    baseUrl = '/bizType/' + bizTypeId + '/' + type + '-course-table/semester/' + semesterId + '/print-data/';
    getDataUrl = '/bizType/' + bizTypeId + '/' + type + '-course-table/get-data';

  }

  var tagInfo = {};
  if ($("#weeks").length != 0) {
    tagInfo = getSelectWeeks(ids, bizTypeId, semesterId, getDataUrl, personId, type);
  }

  var $table;
  var percent = 0;
  //第一组
  function func(times,arr,group) {
    if (times > arr.length - 1) {
      return;
    }
    let url = '';
    let data = {};
    if(((type === 'student'||type ==='headTeacher') && personId)) {
      times++;
      url = window.CONTEXT_PATH + baseUrl;
      data = {
        semesterId: semesterId,
        hasExperiment : $("input[name='hasExperiment']:checked").val() === '1'
      }
      if(type ==='headTeacher'){
        data = {
          semesterId: semesterId,
          ids:ids.join(","),
          hasExperiment : $("input[name='hasExperiment']:checked").val() === '1'
        }
      }
    }else if(type === 'stdAdminclass'){
      times++;
      url = window.CONTEXT_PATH + baseUrl;
      data = {
        studentId: personId,
        semesterId: semesterId,
        bizTypeId: bizTypeId,
        hasExperiment : $("input[name='hasExperiment']:checked").val() === '1'
      }
    }else if (type === 'department' || type === 'major'){
      url = window.CONTEXT_PATH + baseUrl;
      data = {
        bizTypeId: bizTypeId,
        semesterId: semesterId,
        id: arr[times++],
      }
    }else if(type === 'lesson'){
      url = window.CONTEXT_PATH + baseUrl;
      var idTemp = arr[times++];
      data = {
        bizTypeId: bizTypeId,
        semesterId: semesterId,
        ids: idTemp,
      }
    }else if (type === 'parent' || type === 'teacher'){
      var idTemp = arr[times++];
      url = window.CONTEXT_PATH + baseUrl + idTemp;

      data = {
        bizTypeId: bizTypeId,
        semesterId: semesterId,
        id: idTemp,
      }
      if(type === 'teacher'){
        data['hasExperiment'] = $("input[name='hasExperiment']:checked").val() === '1'
      }
    } else if(type == 'teacherAdminclass' || type == 'studentAdminclass'){
      url = window.CONTEXT_PATH + baseUrl + arr[times++]
      data = {
        hasExperiment : $("input[name='hasExperiment']:checked").val() === '1',
        bizTypeId: bizTypeId
      };
    }
    else if(type === 'teacherRoom' || type === 'studentRoom'){
      url = window.CONTEXT_PATH + baseUrl + arr[times++]
      data = {
        hasExperiment : $("input[name='hasExperiment']:checked").val() === '1',
        bizTypeId: bizTypeId
      };
    }
    else {
      url = window.CONTEXT_PATH + baseUrl + arr[times++]
      data = {
        hasExperiment : $("input[name='hasExperiment']:checked").val() === '1'
      };
    }
    $.ajax({
      url: url,
      data: data,
      success: function (res) {
        // if ($("#courseTypeAssocs").length != 0) {
        let currentTableVm = (type === 'student' || type === 'headTeacher') &&  personId ? res[type + 'TableVms'] :   res[type + 'TableVm'];
        if(type === 'headTeacher'  &&  personId){
          currentTableVm = res['student'+'TableVms'];
        }

        if(currentTableVm){
          if(type === 'lesson'){
            currentTableVm = currentTableVm[0];
            let activities = JSON.parse(JSON.stringify(currentTableVm.activities));
            let lessonSearchVms = JSON.parse(JSON.stringify(currentTableVm.lessonSearchVms));
            courseTableDataList.push({
              activities: activities,
              courseTablePrintConfigs: currentTableVm.courseTablePrintConfigs,
              lessonSearchVms: lessonSearchVms,
              credits: currentTableVm.credits,
              tableId: tableId,
              lessonNamePrint: currentTableVm.lessonNamePrint,
              taskPeopleNumPrint: currentTableVm.taskPeopleNumPrint,
              stdCountPrint: currentTableVm.stdCountPrint,
              practiceWeekScheduleTexts: currentTableVm.practiceWeekScheduleTexts
            });

            currentTableVm.id = tableId;
            if(!$table){
              $table = drawTable(currentTableVm, type);
            }

            newCourseTable(currentTableVm, type, $table, tagInfo);
            renderTdStyle(currentTableVm.timeTableLayout, $table);
          }else if((type === 'student' || type==='headTeacher') && personId){ //学生端-我的课表
            var activitiesStd = [];
            var lessonSearchVmsStd = [];
            var practiceWeekScheduleTextsStd = [];
            var ids = [];

            currentTableVm.forEach(function(item){
              activitiesStd = activitiesStd.concat(item.activities);
              lessonSearchVmsStd = lessonSearchVmsStd.concat(item.lessonSearchVms);
              practiceWeekScheduleTextsStd = practiceWeekScheduleTextsStd.concat(item.practiceWeekScheduleTexts);
              ids.push(item.id);
            });

            var newIds = ids.sort(function(a, b){
              return a - b;
            })

            activitiesStd = JSON.parse(JSON.stringify(activitiesStd));
            lessonSearchVmsStd = JSON.parse(JSON.stringify(lessonSearchVmsStd));

            var newCurrentTableVm = {
              activities: activitiesStd,
              courseTablePrintConfigs: currentTableVm[0].courseTablePrintConfigs,
              lessonSearchVms: lessonSearchVmsStd,
              credits: currentTableVm.credits,
              tableId:  newIds.join('-'),
              lessonNamePrint: currentTableVm[0].lessonNamePrint,
              taskPeopleNumPrint: currentTableVm[0].taskPeopleNumPrint,
              stdCountPrint: currentTableVm[0].stdCountPrint ,
              timeTableLayout:  currentTableVm[0].timeTableLayout,
              id: newIds.join('-'),
              practiceWeekScheduleTexts: practiceWeekScheduleTextsStd,
              grade: currentTableVm[0].grade,
              department: currentTableVm[0].department,
              major: currentTableVm[0].major,
              adminclass: currentTableVm[0].adminclass,
              code: currentTableVm[0].code,
              name: currentTableVm[0].name,
            }

            courseTableDataList.push(newCurrentTableVm);

            let $table = drawTable(newCurrentTableVm, type);
            newCourseTable(newCurrentTableVm, type, $table, tagInfo);
            renderTdStyle(newCurrentTableVm.timeTableLayout, $table);
          }else{
            let activities = JSON.parse(JSON.stringify(currentTableVm.activities));
            let lessonSearchVms = JSON.parse(JSON.stringify(currentTableVm.lessonSearchVms));

            if (currentTableVm.arrangedLessonSearchVms && currentTableVm.arrangedLessonSearchVms.length) {
              currentTableVm.arrangedLessonSearchVms.forEach(function (item) {
                if (item.id) {
                  lessons[item.id] = item;
                }
              });
            }

            courseTableDataList.push({
              activities: activities,
              courseTablePrintConfigs: currentTableVm.courseTablePrintConfigs,
              lessonSearchVms: lessonSearchVms,
              credits: currentTableVm.credits,
              tableId: currentTableVm.dataId ? (currentTableVm.dataId).toString().replaceAll(',', '-') : currentTableVm.id,
              lessonNamePrint: currentTableVm.lessonNamePrint,
              taskPeopleNumPrint: currentTableVm.taskPeopleNumPrint,
              stdCountPrint: currentTableVm.stdCountPrint
            });
            // }
            // res[type + 'TableVm'].id = res[type + 'TableVm'].id
            let $table = drawTable(currentTableVm, type);
            newCourseTable(currentTableVm, type, $table, tagInfo);
            renderTdStyle(currentTableVm.timeTableLayout, $table);
          }

        }else{
          let activities = JSON.parse(JSON.stringify(res.activities));
          let lessonSearchVms = JSON.parse(JSON.stringify(res.lessonSearchVms));

          courseTableDataList.push({
            activities: activities,
            courseTablePrintConfigs: res.courseTablePrintConfigs,
            lessonSearchVms: lessonSearchVms,
            credits: res.credits,
            tableId: res.dataId ? (res.dataId).toString().replaceAll(',', '-') : res.id,
            lessonNamePrint: res.lessonNamePrint,
            taskPeopleNumPrint: res.taskPeopleNumPrint,
            practiceWeekScheduleTexts: res.practiceWeekScheduleTexts

          });
          // }
          let $table = drawTable(res, type);
          newCourseTable(res, type, $table, tagInfo);
          renderTdStyle(res.timeTableLayout, $table)
        }
        if (bizTypeId) {
          if(group === 'group1'){
            i1 = times;
          }else if(group === 'group2'){
            i2 = times;
          }else if(group === 'group3'){
            i3 = times;
          }else if(group === 'group4'){
            i4 = times;
          }else if(group === 'group5'){
            i5 = times;
          }
          percent ++;
          updateProgress(percent)
        } else {
          $(".semester-container").html(semesterName);
        }
        func(times,arr)
      }
    })
  }

  func(i1,arr1,'group1');
  func(i2,arr2,'group2');
  func(i3,arr3,'group3');
  func(i4,arr4,'group4');
  func(i5,arr5,'group5');

  if (bizTypeId) {

    $("#progress-bar-modal").modal({
      backdrop: false,
      show: false
    });

    $("#progress-bar-modal").modal('show');
  }

  if ($("#courseTypeAssocs").length != 0) {
    $("#courseTypeAssocs").selectize({
      plugins:['remove_button'],
      onChange: function (values) {
        $(".table tbody tr td.td-content .tdHtml").empty();
        $(".table tbody tr td.td-content .tdHtml").css('font-size', '12px');
        $(".course-table-remark").empty();
        $(".course-table-credits").empty();
        filterCourseTypeAndWeek(type, tagInfo, true);
      }
    });
  }

  return tagInfo;
};


var drawRemarkAndCredits = function (lessonSearchVms, tableId, isFilter, courseMap) {

  var $credits = $("#"+tableId+"-div").find('.course-table-credits');

  if (isFilter) {
    var allCredits = 0;
    for (var key in courseMap) {
      allCredits += Number(courseMap[key]);
    }
    $credits.html('学分为'+allCredits);
  }
}

var getDrawPlateCourseTableData = function (id, bizTypeId, semesterId, type, plateNameLike) {
  var semesterName = '';
  if(id != null){
    var $oneCourseTalbe = $('<div class="paging export-content" style="padding-bottom: 30px;page-break-before: always;" id="' + id + '-div"></div>');
    $('.table-container').append($oneCourseTalbe);
  }
  $('#print').click(function () {
    PrintHelper.print();
  });

  $.ajax({
    async: false,
    url: window.CONTEXT_PATH + '/ws/semester/get/' + semesterId,
    success: function (res) {
      semesterName = res.nameZh;
    }
  });

  var baseUrl = '/bizType/' + bizTypeId + '/plate-course-schedule/semester/' + semesterId + '/print-data';

  $.ajax({
    url: window.CONTEXT_PATH + baseUrl,
    type: 'get',
    data: {
      plateNameLike: plateNameLike,
      courseId: id,
      hasExperiment : $("input[name='hasExperiment']:checked").val() === '1'
    },
    success: function (res) {
      var $table = drawTable(res[type + 'TableVm'], type);
      newCourseTable(res[type + 'TableVm'], type, $table);
    }
  });

};

function handleActivity(activities, configArr, configMap) {
  var showActivities = [];
  _.each(activities, function (activity){
    var startUnit = activity.startUnit;
    var endUnit = activity.endUnit;
    var start = configMap[startUnit];
    var end = configMap[endUnit];

    if (start !== end) {
      var newAct = JSON.parse(JSON.stringify(activity));
      newAct.endUnit = _.max(configArr[start]);
      newAct.startIndex = false
      newAct.endIndex = true
      let unitTime = setUnitTime(newAct)
      newAct.startTime = unitTime.startTime
      newAct.endTime = unitTime.endTime
      showActivities.push(newAct);

      for (var ind = start + 1; ind <= end; ind ++) {
        var newAct2 = JSON.parse(JSON.stringify(activity));
        if (configArr[ind].indexOf(endUnit) !== -1) {
          newAct2.startUnit = configArr[ind][0];
          newAct2.startIndex = true
          newAct2.endIndex = false
          let unitTime = setUnitTime(newAct2)
          newAct2.startTime = unitTime.startTime
          newAct2.endTime = unitTime.endTime
          showActivities.push(newAct2);
          return;
        } else {
          newAct2.startUnit = configArr[ind][0];
          newAct2.endUnit = _.max(configArr[ind]);
          newAct2.startIndex = true
          newAct2.endIndex = true
          let unitTime = setUnitTime(newAct2)
          newAct2.startTime = unitTime.startTime
          newAct2.endTime = unitTime.endTime
          showActivities.push(newAct2);
        }
      }
    } else {
      showActivities.push(activity);
    }
  });

  showActivities.sort(handleSortActivities);

  return showActivities;
}


function getTimeText(time) {
  if((time+'').includes(":")){
    return time;
  }
  var hours = parseInt(time/100);
  var minutes = time%100;
  return hours + ':' + (minutes == 0 ? '00' : (parseInt(minutes/10) == 0 ? '0'+(minutes) : ''+(minutes)));
}

function setUnitTime(unitOption) {
  let startTime = unitOption.startTime+''
  let endTime = unitOption.endTime+''
  let startUnit = unitOption.startUnit
  let endUnit = unitOption.endUnit
  startTime = Number(startTime.replace(':', ''))
  endTime = Number(endTime.replace(':', ''))

  if (unitOption.startIndex) {
    _.each(commonUnits, function (unit) {
      if (unit.indexNo == startUnit) {
        startTime = unit.startTime;
      }
    });
  }
  if (unitOption.endIndex) {
    _.each(commonUnits, function (unit) {
      if (unit.indexNo == endUnit) {
        endTime = unit.endTime;
      }
    });
  }
  return {
    startTime: getTimeText(startTime),
    endTime: getTimeText(endTime)
  };
}

function handleSortActivities(a, b) {
  if(a.lessonId <0){
    return 1;
  }
  if(b.lessonId <0){
    return -1;
  }
  if (a.lessonCode == b.lessonCode) {
    var aWeekIndex = a.weekIndexes.length > 0 ? a.weekIndexes[0] : 0;
    var bWeekIndex = b.weekIndexes.length > 0 ? b.weekIndexes[0] : 0;
    if (aWeekIndex > bWeekIndex) {
      return 1;
    } else {
      return -1;
    }
  } else {
    if (a.lessonCode > b.lessonCode) {
      return 1;
    } else {
      return -1;
    }
  }
}

function handleAdminclassActivity(activities, configMap) {
  var showActivities = [];
  var activitiesGroup = _.groupBy(activities, function (activity) {
    activity.segmentIndex = configMap[activity.startUnit];
    return activity.courseCode + ':' + activity.weekday + ':' + activity.segmentIndex
  });
  for(var key in activitiesGroup){
    var tempActivitiesGroup =  _.sortBy(activitiesGroup[key], 'groupNum');
    activitiesGroup[key] = tempActivitiesGroup;
  }
  for (var key1 in activitiesGroup) {
    var activityList = activitiesGroup[key1];
    if (activityList.length == 1) {
      showActivities.push(activityList[0]);
    } else {
      var lessonActivityGroup = _.groupBy(activityList, function (act) {
        return act.lessonCode;
      })

      if (Object.keys(lessonActivityGroup).length == 1) {
        activityList[0].appendStr = [];
        $.each(activityList, function (index, act) {
          if (index != 0) {
            activityList[0].appendStr.push(act)
          }
        })
      } else {
        var weekIndicesDigestParamList = [];
        var lessonNameArray = [];
        var campus = [];
        var stdCount = 0, limitCount = 0
        for (var key in lessonActivityGroup) {
          var weekIndices = [];
          _.each(lessonActivityGroup[key], function (act) {
            weekIndices = weekIndices.concat(act.weekIndexes);
            if(!campus.includes(act.campus)){
              campus.push(act.campus)
            }
          });

          weekIndicesDigestParamList.push({
            weekIndicesGroupId: key1+':'+key,
            weekIndices: _.uniq(weekIndices)
          })

          lessonNameArray.push(lessonActivityGroup[key][0].lessonName);
          stdCount = lessonActivityGroup[key][0].stdCount || 0
          limitCount = lessonActivityGroup[key][0].limitCount || 0
        }
        var weekIndexObj = getWeekIndices(weekIndicesDigestParamList);

        activityList[0].weeksStrArray = _.values(weekIndexObj);
        activityList[0].lessonNameArray = _.values(lessonNameArray);
        activityList[0].campus = campus.join(',');
        activityList[0].stdCount = (activityList[0].stdCount || 0) + stdCount
        activityList[0].limitCount = (activityList[0].limitCount || 0) + limitCount
      }
      showActivities.push(activityList[0])
    }
  }

  return showActivities;
}

function getWeekIndices(weekIndicesDigestParams) {
  var weekIndexObj = [];
  $.ajax({
    url : window.CONTEXT_PATH + "/ws/schedule-table/week-indices-digest",
    type: 'post',
    contentType : 'application/json',
    async: false,
    data: JSON.stringify(weekIndicesDigestParams),
    success: function(res) {
      weekIndexObj = res.result;
    }
  });
  return weekIndexObj;
}

var renderTdStyle = function (timeTableLayout, $table) {
  if (timeTableLayout && timeTableLayout.courseUnitList && timeTableLayout.courseUnitList.length > 0) {
    var unitColorMap = _.groupBy(timeTableLayout.courseUnitList, function (unit) {
      return unit.indexNo
    })
    if($table && $table.length && $table.find('td.dayPartUnit').length){
      $.each($table.find('td.dayPartUnit'), function () {
        var unit = unitColorMap[$(this).text()]
        if (unit && unit.length > 0 && unit[0].color) {
          $(this).css({'background': unit[0].color})
        }
      })
    }

  }
}

var getTagEle = function(lessonId, tagInfo){
  var tagStr = '<div class="tag-info">';
  var flag = false;

  tagInfo = tagInfo ? tagInfo : {};

  if(tagInfo.cultivateType){
    tagInfo.cultivateType.forEach(function(type){
      if (type.lessonId === lessonId){
        tagStr += '<span>'+ type.nameZh +'</span>';
        flag = true;
      }
    })
  }

  if(tagInfo.retake && tagInfo.retake.includes(lessonId)){
    tagStr += '<span>重修</span>';
    flag = true;
  }

  if (tagInfo.repair && tagInfo.repair.includes(lessonId)) {
    tagStr += '<span>复修</span>';
    flag = true;
  }

  if(tagInfo.notAttend && tagInfo.notAttend.includes(lessonId)){
    tagStr += '<span>免听</span>';
    flag = true;
  }


  if(true){
    tagStr += '</div>'
  }else{
    tagStr = '';
  }

  return tagStr;
}

var newCourseTable = function (options, type, $table, tagInfo) {
  var noNormal = {};
  var config = options.courseTablePrintConfigs;
  var configArr = [], configMap = {};

  $.each(config,function (i,val) {
    $.each(val.unitGroup,function (index, items) {
      configArr.push(items);
      $.each(items, function (k, item) {
        if (k != 0) {
          noNormal[item] = k;
        }
      })
    });
  });

  $.each(configArr, function (conInd, arr){
    _.each(arr, function (conf){
      configMap[conf] = conInd;
    });
  });
  commonUnits = options.timeTableLayout ? options.timeTableLayout.courseUnitList : [];

  // 处理可分割显示的数据
  var activities = handleActivity(options.activities, configArr, configMap);
  // var activities = options.activities;
  // 如果为班级课表，根据课程进行合并，教学任务相同，周次取并集，教学任务不同周次用或显示
  if (type == 'adminclass' || type === 'stdAdminclass' || type === 'teacherAdminclass' || type == 'studentAdminclass') {
    activities = handleAdminclassActivity(activities, configMap);
  } else {
    for (var i = 0; i < activities.length - 1; i++) {
      var act1 = activities[i];
      if (act1 == null) {
        continue;
      }
      var weekday1 = act1.weekday;
      var startUnit1 = act1.startUnit;
      act1.appendStr = [];

      for (var j = i + 1; j < activities.length; j++) {
        var act2 = activities[j];
        if (act2 == null) {
          continue;
        }

        var weekday2 = act2.weekday;
        var startUnit2 = act2.startUnit;
        if (act1.courseCode == act2.courseCode && weekday1 == weekday2 && startUnit1 == startUnit2) {
          if ((type == 'teacher'  || type == 'student' || type == 'room'  || type === 'teacherRoom' || type === 'studentRoom') && act1.lessonCode == act2.lessonCode) {
            act1.appendStr.push(act2);
            activities[j] = null;
          } else if (type == 'student' && act1.teachers.join(',') == act2.teachers.join(',')) {
            act1.appendStr.push(act2);
            activities[j] = null;
          } else if ((type =='room' || type === 'teacherRoom' || type === 'studentRoom') && act1.teachers.join(',') == act2.teachers.join(',') && act1.weekIndexes.join(",") == act2.weekIndexes.join(',') ) {
            act1.weeksStrArray = act1.weeksStrArray || [act1.weeksStr];
            act1.weeksStrArray.push(act2.weeksStr);
            act1.lessonNameArray = act1.lessonNameArray || [act1.lessonName];
            act1.lessonNameArray.push(act2.lessonName);
            var stdCount1 = act1.stdCount || 0
            var stdCount2 = act2.stdCount || 0
            var limitCount1 = act1.limitCount || 0
            var limitCount2 = act2.limitCount || 0
            act1.stdCount = stdCount1 + stdCount2
            act1.limitCount = limitCount1 + limitCount2
            activities[j] = null;
          }
        }
      }
    }
  }

  $.each(activities, function (index, activity) {
    var $tbody = $table.find('tbody');
    if (!activity) {
      return true;
    }

    var plateName = activity.plateName || "";
    var courseName = activity.courseName || "";
    var courseCode = activity.courseCode || "";
    var lessonCode = activity.lessonCode || "";
    var lessonId = activity.lessonId || "";
    var minorCourse = '';
    //小项课
    if(lessons && lessons[activity.lessonId] && lessons[activity.lessonId].minorCourse){
      minorCourse = lessons[activity.lessonId].minorCourse.nameZh ? lessons[activity.lessonId].minorCourse.nameZh : ''
    }

    var room = activity.room ? (activity.room + '&nbsp;') : "";
    var campus = activity.campus ? (activity.campus + '&nbsp;') : "";

    var teachers = "";
    var scheduleWeeksInfo = activity.scheduleWeeksInfo ? ('(' + activity.scheduleWeeksInfo + ')' + '&nbsp;') : '';

    if (type != 'plateCourse') {
      teachers = (activity.teachers.length > 0 && activity.teachers != null) ? activity.teachers.join("/") : "";
    }

    var groupNum = activity.groupNum !== null && activity.groupNum !== '' ? '#' + activity.groupNum + '&nbsp;' : '';
    var weeksStr = activity.weeksStr ? "(" + activity.weeksStr + "周)" : "";
    var campusName = activity.campusName ? activity.campusName + '&nbsp;' : '';
    var weekdayStr = activity.weekday ? activity.weekday + '&nbsp;' : '';
    var totalCount = activity.totalCount ? activity.totalCount + '人' : '';
    var overUnit = '';
    // if(activity.startTime && activity.endTime){
    //    overUnit = '('+ activity.startTime + '-' + activity.endTime + ')&nbsp;';
    // } else{
    overUnit = '('+ activity.startUnit + '-' + activity.endUnit + '节&nbsp;' + activity.startTime + '-' + activity.endTime + ')';
    // }

    var $tdHtml = '';
    if(noNormal.hasOwnProperty(activity.startUnit)){
      $tdHtml = $tbody.find('.' + (activity.startUnit -noNormal[activity.startUnit])).find('td.'+activity.weekday+' .tdHtml');
    } else {
      $tdHtml = $tbody.find('.' + activity.startUnit).find('td.'+activity.weekday+' .tdHtml');
    }

    // if ($tdHtml.html() != "") {
    //   $tdHtml.append('<br/>');
    // }

    var lessonName = '';
    var stdCountStr = '';
    if(options.lessonNamePrint) {
      if (Array.isArray(activity.lessonNameArray)) {
        lessonName= '<div>' +activity.lessonNameArray.join(',') +'</div>';
      } else {
        lessonName= '<div>'+activity.lessonName+'</div>';
      }
    }

    //taskPeopleNumPrint 和 stdCountPrint都表示人数是否显示
    if(options.taskPeopleNumPrint || options.stdCountPrint){
      var stdCount = activity.stdCount ? activity.stdCount : 0;
      var limitCount = activity.limitCount ? activity.limitCount : 0;
      stdCountStr = '<div>人数:'+ stdCount +'/'+ limitCount +'</div>'
    }

    var appendStrs = '';
    if (activity.appendStr && activity.appendStr.length > 0) {
      var appendStr = [];
      if (activity.weeksStrArray) {
        appendStr.push(courseName + '&nbsp;' + lessonCode);
      }
      $.each(activity.appendStr, function (ind, ac) {
        var str = '';
        var childGroupNum = ac && ac.groupNum !== null && ac.groupNum !== undefined && ac.groupNum !== 'undefined' && ac.groupNum !== 'null' ?  '#' + ac.groupNum + '&nbsp;' : ''
        var over2UnitStr = '('+ activity.startUnit + '-' + ac.endUnit + '节&nbsp;' + ac.startTime + '-' + ac.endTime + ')';
        str = childGroupNum;
        str += (ac.weeksStr && ac.weeksStr != null) ? "(" + ac.weeksStr + "周)" : "";
        str += over2UnitStr != null  ? '&nbsp;' + over2UnitStr : '';
        str += ac.campus != null ? '&nbsp' + ac.campus : '';
        str += ac.room != null ? '&nbsp;' + ac.room + '&nbsp;' : "";
        str += (ac.teachers != null && ac.teachers.length) ? '&nbsp;' + ac.teachers.join("/") : "";
        appendStr.push(str);
      });
      appendStrs = appendStr.join("<br/>");

    }

    if (activity.weeksStrArray) {
      var uniqWeeksArray = _.uniq(activity.weeksStrArray);
      lessonCode = "";
      room = "";
      teachers = "";
      weeksStr = "";
      // if (type == 'adminclass' || type === 'stdAdminclass' || type === 'teacherAdminclass' || type == 'studentAdminclass') {
      //   overUnit = '';
      // }
      for (var i = 0; i < uniqWeeksArray.length; i++) {
        weeksStr += "(" + uniqWeeksArray[i] + "周)";
        if (i < uniqWeeksArray.length - 1) {
          weeksStr += "或";
        }
      }
    }

    $tdHtml.attr('lessonid',lessonId)
    if (type === 'adminclass' || type === 'stdAdminclass' || type === 'teacherAdminclass' || type == 'studentAdminclass') {
      // $tdHtml.append(courseName + '&nbsp;' + lessonCode + '<br/>' + weeksStr + '&nbsp;'+ overUnit + room + teachers);
      let contentStr = '<div class="course-name">'+courseName + '<sup class="minor-courses">'+ minorCourse +'</sup>' +'</div>' +
          '<div>'+lessonCode+'</div>' +
          '<div>'+ groupNum + weeksStr + '&nbsp;' + overUnit  + '&nbsp;'+ campus + room + '&nbsp;' + teachers + '</div>'
      $tdHtml.append(contentStr);

      if (activity.weeksStrArray) {
        $tdHtml.append(lessonName);
      }
      if (appendStrs != '') {
        $tdHtml.append(appendStrs);
      }

      if (!(activity.weeksStrArray && appendStrs == '')) {
        $tdHtml.append(lessonName);
      }

      $tdHtml.append(stdCountStr);
    } else if (type === 'room' || type === 'teacherRoom' || type === 'studentRoom') {
      //判断课程是不是属于当前的业务类型
      var currentLessonType = '';
      var currentLesson = lessons[activity.lessonId];
      if (currentLesson && currentLesson.bizType && currentLesson.bizType.id !== currentBizTypeId) {
        currentLessonType = '&nbsp;[' + currentLesson.bizType.nameZh + ']';
      }

      let contentStr = '<div class="course-name">' + courseName + currentLessonType +'<sup class="minor-courses">'+ minorCourse +'</sup>' +'</div>' +
          '<div>' + lessonCode + '</div>' +
          '<div>'+ groupNum + weeksStr + '&nbsp;' + overUnit + '&nbsp;' + campus + room + '&nbsp;' + teachers + '</div>'
      $tdHtml.append(contentStr);
      if (activity.weeksStrArray) {
        $tdHtml.append(lessonName);
      }
      if (appendStrs != '') {
        $tdHtml.append(appendStrs);
      }

      if (!(activity.weeksStrArray && appendStrs == '')) {
        $tdHtml.append(lessonName);
      }

      $tdHtml.append(stdCountStr);
    } else if(type === 'student' || type ==='headTeacher' || type === 'parent'){
      var tagStr = getTagEle(lessonId, tagInfo);
      let contentStr = '<div class="course-name">'+ tagStr + courseName + '<sup class="minor-courses">'+ minorCourse +'</sup>' +'</div>' +
          '<div>'+lessonCode+'</div>' +
          '<div>'+ groupNum +weeksStr + '&nbsp;' + overUnit  + '&nbsp;'+ campus + room + '&nbsp;' + teachers + '</div>'
      $tdHtml.append(contentStr);

      if (appendStrs != '') {
        $tdHtml.append(appendStrs);
      }

      if (!(activity.weeksStrArray && appendStrs == '')) {
        $tdHtml.append(lessonName);
      }

      $tdHtml.append(stdCountStr);
    }else if (type === 'teacher') {

      let contentStr = '<div class="course-name">'+courseName + '<sup class="minor-courses">'+ minorCourse +'</sup>' +'</div>' +
          '<div>'+lessonCode+'</div>' +
          '<div>' + groupNum +weeksStr + '&nbsp;' + overUnit  + '&nbsp;'+ campus + room + '&nbsp;' + teachers + '</div>'
      $tdHtml.append(contentStr);
      if (appendStrs != '') {
        $tdHtml.append(appendStrs);
      }

      if (!(activity.weeksStrArray && appendStrs == '')) {
        $tdHtml.append(lessonName);
      }

      $tdHtml.append(stdCountStr);

    } else if (type === 'plateCourse') {
      $tdHtml.append('[' + plateName + ']' + '<br/>' + courseName + '[' + courseCode + ']' + '<sup class="minor-courses">'+ minorCourse +'</sup>' +'<br/>' +
          scheduleWeeksInfo + weekdayStr + overUnit + campusName + '<br/>' + totalCount);
      // $tdHtml.append(',' + overUnit);
    } else if(type === 'department' || type === 'major' || type === 'lesson'){
      let contentStr = '<div class="course-name">'+courseName + '<sup class="minor-courses">'+ minorCourse +'</sup>' +'</div>' +
          '<div>'+lessonCode+'</div>' +
          '<div>'+ groupNum +weeksStr + '&nbsp;' + overUnit  + '&nbsp;'+ campus + room + '&nbsp;' + teachers + '</div>';
      $tdHtml.append(contentStr);

      if (appendStrs != '') {
        $tdHtml.append(appendStrs);
      }

      if (!(activity.weeksStrArray && appendStrs == '')) {
        $tdHtml.append(lessonName);
      }

      $tdHtml.append(stdCountStr);
    }

    var baseTdHeight = 44;
    var unitsHeight = baseTdHeight * Number($tdHtml.closest('td').attr("rowspan"));
    var height = parseInt($tdHtml.outerHeight());
    var tdHeight = parseInt($tdHtml.closest('td').outerHeight());

    var fontSize = 12;
    $tdHtml.css("font-size") ? fontSize = Number($tdHtml.css("font-size").split('p')[0]) : '';
    var count = 0;

    while (height >= (tdHeight-1) && tdHeight > unitsHeight && count < 6) {
      fontSize = Number($tdHtml.css("font-size").split('p')[0]);
      if (type === 'plateCourse') {
        $tdHtml.css('font-size', '11px');
      } else {
        $tdHtml.css('font-size', (fontSize - 1) + 'px');
        if (fontSize > 7) {
          $tdHtml.find('.lessonNameFontSize').css('font-size', (fontSize - 3) + 'px');
          $tdHtml.find('.stdCountFontSize').css('font-size', (fontSize - 3) + 'px');
        } else {
          $tdHtml.find('.lessonNameFontSize').css('font-size', (fontSize - 1) + 'px');
          $tdHtml.find('.stdCountFontSize').css('font-size', (fontSize - 1) + 'px');
        }
      }
      height = parseInt($tdHtml.outerHeight());
      tdHeight = parseInt($tdHtml.closest('td').outerHeight());
      count++;
    }
  });


  $(".table-container tbody tr .td-content").each(function (){
    if($(this).children(".tdHtml").html()){
      let color = lessonColors[$(this).children(".tdHtml").attr('lessonid')]
      $(this).children(".tdHtml").css({'min-height':($(this).height()-4)+'px'});
      if(color){
        $(this).children(".tdHtml").css({'background': color ,'border-left': '2px solid '+ color.replace('0.2','1')});
      }
    }
  })
};

var getRemark = function(type, lessonSearchVms, practiceWeekScheduleTexts){
  //课表里如果有任务，则显示备注，备注由任务的课程名称、任务代码以及任务的建议周次组成，如果该任务有备注，则添加上任务备注
  //每个任务前由序列号标记
  var remark = '';
  ((lessonSearchVms && lessonSearchVms.length > 0)
      || (practiceWeekScheduleTexts && practiceWeekScheduleTexts.length > 0))
      ? remark = "备注:" : remark = "";

  $.each(lessonSearchVms, function (index, vm) {
    var suggestInfo =  "";
    var vmRemark = ""
    suggestInfo = vm.suggestScheduleWeeksInfo;
    suggestInfo = (suggestInfo && vm.teacherAssignmentString) ? suggestInfo + (vm.teacherAssignmentString ? (' ' + vm.teacherAssignmentString) : '')  : vm.teacherAssignmentString;
    suggestInfo = suggestInfo ? `(${suggestInfo})` : '';
    vm.remark ? (vmRemark = "任务备注:&nbsp;(" + vm.remark + ")") : "";

    if (type === 'student'|| type ==='headTeacher' || type === 'adminclass'|| type === 'parent' || type === 'lesson' || type === 'teacherAdminclass' || type == 'studentAdminclass') {
      remark += ` ${index + 1}.${vm.course.nameZh} ${vm.code} ${suggestInfo} ${vmRemark}`
    }

    if (type === 'teacher'|| type === 'major' || type === 'department') {
      remark += ` ${index + 1}.${vm.course ? vm.course.nameZh : ''} ${vm.code} ${suggestInfo} ${vmRemark}`
    }
  });

  // 实践专周备注
  if (practiceWeekScheduleTexts && practiceWeekScheduleTexts.length > 0) {
    var ind = 1
    if (lessonSearchVms && lessonSearchVms.length > 0) {
      ind = lessonSearchVms.length + 1
    }
    $.each(practiceWeekScheduleTexts, function (i, practiceWeek) {
      remark += '&nbsp;' + (ind + i) + '.' + '实践专周:&nbsp;' + practiceWeek
    })
  }

  return remark;
}

//画课表的样式以及课表上面和下面的内容
var drawTable = function (option, type) {
  var config = option.courseTablePrintConfigs;
  var schoolName = globalVariable.schoolName || '';

  option.id = option.dataId ? (option.dataId).toString().replaceAll(',', '-') : option.id;

  var $oneCourseTalbe = $('#' + option.id + '-div');
  if (type === 'plateCourse') {
    $oneCourseTalbe = $('#' + option.courseId + '-div');
  }

  var $tableTop = $('<div class="form-group text-center">' +
      '<p style="font-size:20px; margin-bottom: 0px; word-break: break-all; white-space: normal;"><span class="tableTopName"></span>(<span class="semester-container"></span>)</p>' +
      '</div><div><div class="table-head-info"></div></div>');

  var remark = getRemark(type, option.lessonSearchVms, option.practiceWeekScheduleTexts);
  var $remark = $('<div class="course-table-fontSize course-table-remark ' + (remark == '' ? 'hide' : '') + '" style="margin-top: 5px;">' + remark + '</div>')

  if (type === 'room' || type === 'teacherRoom' || type === 'studentRoom') {
    $tableTop.find('.table-head-info').append(
        '<span style="width:25%"><label>教室:</label><span class="export-title">' + option.name + '</span></span>'+
        '<span style="width:30%"><label>校区/教学楼:</label><span>' + option.campus+'/'+option.building + '</span></span>' +
        '<span style="width:35%"><label>教室类型:</label><span>' + option.type + '</span></span>' +
        '<span style="width:10%"><label>座位数:</label><span>' + option.seatsForLesson + '</span></span>'
    );
    $tableTop.find(".tableTopName").html(schoolName + '教室课表')
  }
  if (type === "teacher") {
    $tableTop.find('.table-head-info').append('<span  style="width:50%;"><label>教师所属部门：</label><span>' + option.department + '     </span></span>' +
        '<span  style="width:50%;"><label>教师：</label><span class="export-title">' + option.name + '     </span></span>');
    $tableTop.find(".tableTopName").html(schoolName + '教师课表')

  }
  if (type === "student") {
    $tableTop.find('.table-head-info').append('<span style="width:10%"><label>年级：</label><span>' + option.grade + '</span>     </span>' +
        '<span style="width:20%"><label>学院：</label><span>' + option.department + '</span>     </span>' +
        '<span style="width:20%"><label>专业：</label><span>' + option.major + '</span>     </span>' +
        '<span style="width:20%"><label>班级：</label><span>' + option.adminclass + '</span>     </span>' +
        '<span style="width:20%"><label>学号：</label><span>' + option.code + '</span>     </span>' +
        '<span style="width:10%"><label>姓名：</label><span class="export-title">' + option.name + '</span>     </span>' +
        '');
    $tableTop.find(".tableTopName").html(schoolName + '学生课表');
  }
  if (type === "adminclass" || type === 'stdAdminclass' || type === 'teacherAdminclass' || type == 'studentAdminclass') {
    $tableTop.find('.table-head-info').append('<span style="width:20%"><label>年级：</label><span>' + option.grade + '</span>     </span>' +
        '<span style="width:25%"><label>学院：</label><span>' + option.department + '</span>     </span>' +
        '<span style="width:25%"><label>专业：</label><span>' + option.major + '</span>     </span>' +
        '<span style="width:25%"><label>班级：</label><span class="export-title">' + option.name + '</span>     </span>' +
        '');
    $tableTop.find(".tableTopName").html(schoolName + '班级课表');
  }
  if (type === "plateCourse") {
    $tableTop.find('.table-head-info').append(
        '<span style="width:50%"><label>板块课:</label><span>' + option.courseName + '</span>     </span>' +
        '<span style="width:50%"><label>板块名称（部分）:</label><span>' + option.plateNameLike + '</span>     </span>'
    );
    $tableTop.find(".tableTopName").html(schoolName + '板块课课表')
  }

  var $table = $('<table class="table courseTable" id="' + option.id + '" style="width: 100%" ><thead>' +
      '<th width="2%"></th>' +
      '<th width="14%">星期一</th>' +
      '<th width="14%">星期二</th>' +
      '<th width="14%">星期三</th>' +
      '<th width="14%">星期四</th>' +
      '<th width="14%">星期五</th>' +
      '<th width="14%">星期六</th>' +
      '<th width="14%">星期日</th>' +
      '</thead><tbody></tbody></table>');
  // $oneCourseTalbe.append($tableTop);
  $oneCourseTalbe.append($table);
  $oneCourseTalbe.append($remark);
  if(!config.length){
    $table.find('tbody').append('<tr><td colspan="8" style="height: 35px;text-align: center;">暂无数据</td></tr>');
  }else{
    $.each(config, function (index, item) {
      // 上午、中午、下午或晚上合并的单元格数 spanNum
      var spanNum = 0;
      $.each(item.unitGroup, function (i, v) {
        spanNum += v.length;
      });

      $.each(item.unitGroup, function (k, units) {
        $.each(units, function (j, unit) {
          var $tr = $('<tr class="' + unit + '"></tr>');
          if (j === 0) {
            $tr.append('<td class="dayPartUnit">' + unit + '</td>');
            for (var i = 1; i <= 7; i++) {

              $tr.append('<td rowspan="' + units.length + '" class="td-content '+i+'" style="position: relative;"><div class="tdHtml"></div></td>')
            }
          } else {
            $tr.append('<td class="dayPartUnit">' + unit + '</td>');
          }
          $table.find('tbody').append($tr);
        })
      })

    })
  }
  return $table;
};

var zip = {
  post: function (title) {
    FormUtil.post({
      form:$("<form></form>"),
      url: window.CONTEXT_PATH + '/utils/msoffice/html-to-docx/convert-batch',
      params: {
        "paramList": JSON.stringify(this.exportDocList()),
        "zipFileName": title || "课表"
      }
    })
  },
  exportDocList: function () {
    var exportDocxList = [];
    $('.export-content').each(function (i) {
      var exportDocx = {
        title: common.getTitle(this),
        html: (common.htmlStr + this.outerHTML + common.endStr).replace(/<br>/g, '<br\/>')
      };
      exportDocxList.push(exportDocx);
    });
    return exportDocxList;

  }
};

var singleDoc = {
  post: function (title) {
    FormUtil.post({
      form:$("<form></form>"),
      url: window.CONTEXT_PATH + '/utils/msoffice/html-to-docx/convert',
      params: {
        'param': JSON.stringify(this.exportDocList(title))
      }
    })
  },
  exportDocList: function (title) {
    var singleDocx = {
      title: title || '课表',
      html: common.htmlStr
    };
    $contents = $('.export-content');
    $contents.each(function (i) {
      singleDocx.html += this.outerHTML;
      if (i !== $contents.length - 1) {
        singleDocx.html += common.pageBreakStr;
      }
    });
    singleDocx.html += common.endStr;
    var newStr = singleDocx.html.replace(/<br>/g, '<br\/>');
    singleDocx.html = newStr;
    return singleDocx;
  }
};

var common = {
  htmlStr: '<!DOCTYPE html>' +
      '<html lang="zh" xmlns="http://www.w3.org/1999/xhtml">' +
      '<head>' +
      '  <style>' +
      '    table {' +
      '      border: 1px solid black;' +
      '      border-spacing: 0;' +
      '      border-collapse: collapse;' +
      '      word-break: break-all;' +
      '      white-space: normal;' +
      '      table-layout: fixed;' +
      '    }' +
      '    thead tr th {' +
      '      text-align: center;' +
      '      vertical-align: middle;' +
      '    }' +
      '    td {' +
      '      border: 1px solid black;' +
      '      font-size: 12px;' +
      '    }' +
      '    .timeArea, .dayPartUnit {' +
      '      width: 2%;' +
      '      text-align: center !important;' +
      '      vertical-align: middle !important;' +
      '    }' +
      '    .dayPartUnit {height: 44px;}' +
      '    .hide {display: none !important;}' +
      '    .lessonNameFontSize, .stdCountFontSize {' +
      '      display: inline-block;' +
      '      font-size: 10px;' +
      '    }' +
      '    .text-center{text-align: center !important;}' +
      '  </style>' +
      '</head>' +
      '<body>',
  endStr: '</body>' +
      '</html>'
  ,
  pageBreakStr: '<div style="page-break-before: always;"></div>',
  getTitle: function (div) {
    return $(div).find('.export-title').text().replace(/^\s+|\s+$/g, "");
  }
};

var exportFile = function (fileType, title) {
  if (fileType.post instanceof Function) {
    fileType.post(title);
  }
};
var compareTime = function(stime, etime) {
  // 转换时间格式，并转换为时间戳
  function tranDate (time) {
    return new Date(time.replace(/-/g, '/')).getTime();
  }
  // 开始时间
  let startTime = tranDate(stime);
  // 结束时间
  let endTime = tranDate(etime);
  let thisDate = new Date();
  let currentTime = thisDate.getFullYear() + '-' + (thisDate.getMonth() + 1) + '-' + thisDate.getDate() + ' ' + thisDate.getHours() + ':' + thisDate.getMinutes();
  let nowTime = tranDate(currentTime);
  if (nowTime < startTime || nowTime > endTime) {
    return false;
  }
  return true;
};

//主修、重修、免听
var organizeTagInfo = function (lesson2CultivateTypeMap, lessonId2Retake, lessonId2Repair, notAttendLessonIds){
  lesson2CultivateTypeMap = lesson2CultivateTypeMap ? lesson2CultivateTypeMap : {};
  lessonId2Retake = lessonId2Retake ? lessonId2Retake : {};
  lessonId2Repair = lessonId2Repair ? lessonId2Repair : {};
  notAttendLessonIds = notAttendLessonIds ? notAttendLessonIds : [];

  var tagInfo = {
    cultivateType: [],
    retake: [],
    repair: [],
    notAttend: []
  };

  for (const key in lesson2CultivateTypeMap) {
    if (Object.hasOwnProperty.call(lesson2CultivateTypeMap, key)) {
      const lesson = lesson2CultivateTypeMap[key];
      var nameZh = $.trim(lesson.nameZh);
      if(nameZh && nameZh !== '主修'){
        tagInfo.cultivateType.push({
          lessonId: Number(key),
          nameZh: nameZh
        });
      }
    }
  }

  for (const key in lessonId2Retake) {
    if (Object.hasOwnProperty.call(lessonId2Retake, key)) {
      if(lessonId2Retake[key]){
        tagInfo.retake.push(Number(key));
      }
    }
  }

  for (const key in lessonId2Repair) {
    if (Object.hasOwnProperty.call(lessonId2Repair, key)) {
      if(lessonId2Repair[key]){
        tagInfo.repair.push(Number(key));
      }
    }
  }


  notAttendLessonIds.forEach(function(lessonId){
    tagInfo.notAttend.push(Number(lessonId))
  })

  return tagInfo;
}


var getSelectWeeks = function(ids, bizTypeId, semesterId,baseUrl, personId, type) {
  let params = {};
  let tagInfo = {};

  if(personId){
    if(type==='headTeacher'){
      params = {
        semesterId: semesterId,
        dataId: personId,
        ids:ids.join(","),
        bizTypeId : bizTypeId
      }
    }else{
      params = {
        semesterId: semesterId,
        dataId: personId,
        bizTypeId : bizTypeId
      }
    }
  }else{
    if(type === 'lesson'){
      params = {
        semesterId: semesterId,
        ids: ids.join(','),
        bizTypeId : bizTypeId
      }
    }else{
      params = {
        semesterId: semesterId,
        dataId: ids[0],
        bizTypeId : bizTypeId
      }
    }

  }
  $.ajax({
    url: window.CONTEXT_PATH + baseUrl ,
    type: 'get',
    async: false,
    data: params,
    success: function (res) {
      weekIndices = res.weekIndices;
      currentWeek = res.currentWeek;
      lessonIds = res.lessonIds || [];

      if (res.lessons && res.lessons.length) {
        res.lessons.forEach(function (item) {
          if (item.id) {
            lessons[item.id] = item;
          }
        });
      }

      tagInfo = organizeTagInfo(res.lesson2CultivateTypeMap, res.lessonId2Retake, res.lessonId2Repair, res.notAttendLessonIds);
      let count = 0;
      lessonIds.forEach((id, index) => {
        lessonColors[id] = bgColors[count];
        if (count < bgColors.length - 1) {
          count++
        } else {
          count = 0
        }
      })

      let allweeks = '';
      if (window.LOCALE === 'zh') {
        allweeks = '全部周次'
      }else if(window.LOCALE === 'en') {
        allweeks = 'All Weeks'
      }
      $("#weeks")[0].selectize.clearOptions();
      $("#weeks")[0].selectize.addOption({value: "all", text: allweeks});
      $.each(weekIndices, function () {
        if (window.LOCALE === 'zh') {
          $("#weeks")[0].selectize.addOption({text: '第' + this + '周', value: this});
        } else {
          let self = JSON.stringify(this);
          switch (self) {
            case('1') :
              $("#weeks")[0].selectize.addOption({text: '1st', value: self});
              break;
            case('2') :
              $("#weeks")[0].selectize.addOption({text: '2nd', value: self});
              break;
            case('3') :
              $("#weeks")[0].selectize.addOption({text: '3rd', value: self});
              break;
            default :
              $("#weeks")[0].selectize.addOption({text: self + 'th', value: self});
              break;
          }
        }
      });
      $("#weeks")[0].selectize.addItem('all', true);
      $("#weeks")[0].selectize.refreshOptions(false);
    }
  });


  return tagInfo;
}
var judgeWeek = function ($target) {
  $(".week.lastWeek").attr('disabled', false);
  $(".week.nextWeek").attr('disabled', false);
  if ('1' == $target.val()) {
    $(".lastWeek").attr('disabled', true);
  } else if (weekIndices[weekIndices.length - 1] == $target.val()) {
    $(".nextWeek").attr('disabled', true);
  }
};
var bindWeekEvents = function(type, tagInfo) {

  $(".week-div-opea button.week").unbind('click').on('click', function () {
    $(".week.lastWeek").attr('disabled', false);
    $(".week.nextWeek").attr('disabled', false);
    if ($(this).hasClass('currWeek')) {
      $("#weeks")[0].selectize.addItem(currentWeek);
      if ($("#weeks").val() == 1) {
        $(".week.lastWeek").attr('disabled', true);
      } else if ($("#weeks").val() == weekIndices[weekIndices.length - 1]) {
        $(".week.nextWeek").attr('disabled', true);
      }
    } else if ($(this).hasClass('lastWeek')) {
      if ($("#weeks").val() != 1) {
        $("#weeks")[0].selectize.addItem($("#weeks").val() - 1);
      } else if ($("#weeks").val() == 1) {
        $(this).attr('disabled', true);
      }
    } else if ($(this).hasClass('nextWeek')) {
      if ($("#weeks").val() != weekIndices[weekIndices.length - 1]) {
        $("#weeks")[0].selectize.addItem((parseInt($("#weeks").val()) + 1));
        if ($("#weeks").val() == weekIndices[weekIndices.length - 1]) {
          $(this).attr('disabled', true);
        }
      }
    }
  });
  $("#weeks").unbind('change').on('change', function() {
    judgeWeek($(this));
    $(".table tbody tr td.td-content .tdHtml").empty();
    $(".course-table-credits").empty();
    filterCourseTypeAndWeek(type, tagInfo);
  })
};

var filterCourseTypeAndWeek = function (type, tagInfo, isResetRemark) {
  var selectCourseTypeIds = $("#courseTypeAssocs").val();
  var week = $("#weeks").val();

  if (week == 'all' && !selectCourseTypeIds) {
    $.each(courseTableDataList, function (index, item) {
      newCourseTable({
        'activities': JSON.parse(JSON.stringify(item.activities)),
        courseTablePrintConfigs: item.courseTablePrintConfigs,
        lessonNamePrint: item.lessonNamePrint,
        taskPeopleNumPrint: item.taskPeopleNumPrint,
        stdCountPrint: item.stdCountPrint
      }, type, $("#" + item.tableId), tagInfo);
      drawRemarkAndCredits(item.lessonSearchVms, item.tableId, false);
      if(isResetRemark && index === 0){
        var remark = getRemark(type, item.lessonSearchVms);
        $('.course-table-remark').html(remark)
      }
      $("#" + item.tableId + "-div").find('.course-table-credits').html(item.credits != null ? '学分为：' + item.credits : '');
    });
  } else {
    $.each(courseTableDataList, function (index, item) {
      var activities = _.filter(item.activities, function (activity) {
        if (!selectCourseTypeIds) {
          return week != 'all' ? (activity.weekIndexes != null ? activity.weekIndexes.indexOf(parseInt(week)) != -1 : false) : true;
        } else {
          return (week != 'all' ? (activity.weekIndexes != null ? activity.weekIndexes.indexOf(parseInt(week)) != -1 : false) : true)
              && (activity.courseType == null || selectCourseTypeIds.indexOf(activity.courseType.id + '') == -1)
        }
      });

      var lessonSearchVms = _.filter(item.lessonSearchVms, function (lesson) {
        if (!selectCourseTypeIds) {
          return week != 'all' ? (lesson.suggestScheduleWeeks != null ? lesson.suggestScheduleWeeks.indexOf(parseInt(week)) != -1 : false) : true;
        } else {
          return (week != 'all' ? (lesson.suggestScheduleWeeks != null ? lesson.suggestScheduleWeeks.indexOf(parseInt(week)) != -1 : false) : true)
              && (lesson.courseType == null || selectCourseTypeIds.indexOf(lesson.courseType.id + '') == -1)
        }
      });

      if(isResetRemark && index === 0){
        var remark = getRemark(type, lessonSearchVms);
        $('.course-table-remark').html(remark)
      }

      var courseMap = {};
      _.each(activities, function (activity) {
        if (!courseMap.hasOwnProperty(activity.courseCode)) {
          courseMap[activity.courseCode] = activity.credits;
        }
      });

      _.each(lessonSearchVms, function (lesson) {
        if (lesson.course != null && !courseMap.hasOwnProperty(lesson.course.code)) {
          courseMap[lesson.course.code] = lesson.course.credits;
        }
      });

      newCourseTable({
        'activities': activities,
        courseTablePrintConfigs: item.courseTablePrintConfigs,
        lessonNamePrint: item.lessonNamePrint,
        taskPeopleNumPrint: item.taskPeopleNumPrint,
        stdCountPrint: item.stdCountPrint
      }, type, $("#" + item.tableId), tagInfo);
      if (type === 'teacher' || type === 'room'  || type === 'teacherRoom' || type === 'studentRoom') {
        drawRemarkAndCredits(lessonSearchVms, item.tableId, false, courseMap);
      } else {
        drawRemarkAndCredits(lessonSearchVms, item.tableId, true, courseMap);
      }

    })
  }


  $(".table-container tbody tr .td-content").each(function (){
    if($(this).children(".tdHtml").html()){
      let color = lessonColors[$(this).children(".tdHtml").attr('lessonid')]
      if(color){
        $(this).children(".tdHtml").css({'min-height':($(this).height()-4)+'px','background': color ,'border-left': '2px solid '+ color.replace('0.2','1')});
      } else {
        $(this).children(".tdHtml").css({'background': '#FFFFFF', 'border-left': 'none'});
      }
    } else {
      $(this).children(".tdHtml").css({'background': '#FFFFFF', 'border-left': 'none'});
    }
  })

}

var getSelectizeOptionsNotDel = function(operateObj){
  var obj = {
    onFocus: function(){
      oldValue = this.getValue();
    },
    onBlur: function(){
      if(this.getValue() === ''){
        this.addItem(oldValue, true);
      }
    }
  }

  return Object.assign(obj, operateObj);
}

var getRequest = function () {
  var url = location.search;
  var theRequest = {};
  if (url.indexOf("?") != -1) {
    var str = url.substr(1);
    var strs = str.split("&");
    for (var i = 0; i < strs.length; i++) {
      theRequest[strs[i].split("=")[0]] = decodeURI(strs[i].split("=")[1]);
    }
  }
  return theRequest;
}

$(window).resize(function () {
  $(".table-container tbody tr .td-content").each(function () {
    $(this).children(".tdHtml").css({'min-height': ($(this).height() - 4) + 'px'});
  })
})
