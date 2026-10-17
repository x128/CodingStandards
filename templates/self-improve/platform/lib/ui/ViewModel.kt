package lib.ui

import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel

abstract class ViewModel(dispatcher: CoroutineDispatcher) {
    protected val viewModelScope: CoroutineScope = CoroutineScope(SupervisorJob() + dispatcher)

    fun clear() {
        viewModelScope.cancel()
    }
}
