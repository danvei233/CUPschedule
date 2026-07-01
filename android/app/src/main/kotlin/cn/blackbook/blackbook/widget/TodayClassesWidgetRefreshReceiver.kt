package cn.blackbook.blackbook.widget

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class TodayClassesWidgetRefreshReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        TodayClassesWidgetProvider.refreshAll(context)
    }
}
