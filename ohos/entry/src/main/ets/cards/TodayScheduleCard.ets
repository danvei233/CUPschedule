@Entry
@Component
struct TodayScheduleCard {
  @LocalStorageProp('title') title: string = '今日课程';
  @LocalStorageProp('subtitle') subtitle: string = '打开石大课表同步课程';
  @LocalStorageProp('firstTime') firstTime: string = '--:--';
  @LocalStorageProp('firstCourse') firstCourse: string = '暂无课程';
  @LocalStorageProp('firstPlace') firstPlace: string = '';
  @LocalStorageProp('secondTime') secondTime: string = '';
  @LocalStorageProp('secondCourse') secondCourse: string = '';
  @LocalStorageProp('secondPlace') secondPlace: string = '';

  build() {
    Column({ space: 8 }) {
      Row() {
        Text(this.title)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#111827')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Blank()
      }
      .width('100%')

      Text(this.subtitle)
        .fontSize(12)
        .fontColor('#6B7280')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      this.CourseRow(this.firstTime, this.firstCourse, this.firstPlace, '#B51E23')

      if (this.secondCourse.length > 0) {
        this.CourseRow(this.secondTime, this.secondCourse, this.secondPlace, '#1C7EB2')
      }
    }
    .width('100%')
    .height('100%')
    .padding(14)
    .backgroundColor('#F8FAFF')
    .borderRadius(18)
    .onClick(() => {
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility',
        params: {
          source: 'harmony_form'
        }
      });
    })
  }

  @Builder
  CourseRow(time: string, name: string, place: string, accent: string) {
    Row({ space: 8 }) {
      Column()
        .width(3)
        .height(38)
        .backgroundColor(accent)
        .borderRadius(1)
      Column() {
        Text(time)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(accent)
          .maxLines(1)
        Text(name)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor('#111827')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (place.length > 0) {
          Text(place)
            .fontSize(11)
            .fontColor('#6B7280')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding({
      left: 8,
      right: 8,
      top: 7,
      bottom: 7,
    })
    .backgroundColor('#FFFFFF')
    .borderRadius(4)
  }
}
