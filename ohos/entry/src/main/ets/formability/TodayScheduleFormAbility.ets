import FormExtensionAbility from '@ohos.app.form.FormExtensionAbility';
import formBindingData from '@ohos.app.form.formBindingData';
import formInfo from '@ohos.app.form.formInfo';
import formProvider from '@ohos.app.form.formProvider';
import { Want } from '@ohos.app.ability.Want';

type TodayFormData = Record<string, string>;

const defaultFormData: TodayFormData = {
  title: '今日课程',
  subtitle: '打开石大课表同步课程',
  firstTime: '--:--',
  firstCourse: '暂无课程',
  firstPlace: '',
  secondTime: '',
  secondCourse: '',
  secondPlace: '',
};

export default class TodayScheduleFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    return formBindingData.createFormBindingData(defaultFormData);
  }

  onUpdateForm(formId: string): void {
    formProvider.updateForm(
      formId,
      formBindingData.createFormBindingData(defaultFormData),
    );
  }

  onAcquireFormState(want: Want): formInfo.FormState {
    return formInfo.FormState.READY;
  }
}
