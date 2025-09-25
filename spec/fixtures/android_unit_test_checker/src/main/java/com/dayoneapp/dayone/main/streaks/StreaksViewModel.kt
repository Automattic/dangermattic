package com.dayoneapp.dayone.main.streaks

import android.content.Context
import android.graphics.Bitmap
import androidx.annotation.ColorRes
import androidx.annotation.VisibleForTesting
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.dayoneapp.dayone.di.DatabaseThreadDispatcher
import com.dayoneapp.dayone.domain.JournalRepository
import com.dayoneapp.dayone.domain.SelectedJournalsProvider
import com.dayoneapp.dayone.domain.StreakRepository
import com.dayoneapp.dayone.domain.UserRepository
import com.dayoneapp.dayone.domain.analytics.AnalyticsTracker
import com.dayoneapp.dayone.domain.analytics.InitialContent
import com.dayoneapp.dayone.domain.entry.EntryRepository
import com.dayoneapp.dayone.main.editor.EditorLauncher
import com.dayoneapp.dayone.main.editor.MainActivityLauncher
import com.dayoneapp.dayone.main.navigation.ActivityEventHandler
import com.dayoneapp.dayone.main.navigation.Navigator
import com.dayoneapp.dayone.main.sharedjournals.events.OpenJournalOnTimeline
import com.dayoneapp.dayone.utils.DOStreakCalculator
import com.dayoneapp.dayone.utils.TimeProvider
import com.dayoneapp.dayone.utils.UtilsWrapper
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.io.File
import java.time.DayOfWeek
import java.time.LocalDate
import java.util.Calendar
import javax.inject.Inject

@HiltViewModel
class StreaksViewModel
    @Inject
    constructor(
        @DatabaseThreadDispatcher private val databaseDispatcher: CoroutineDispatcher,
        private val entryRepository: EntryRepository,
        private val journalRepository: JournalRepository,
        private val streakRepository: StreakRepository,
        private val streaksCalculator: DOStreakCalculator,
        private val timeProvider: TimeProvider,
        private val userRepository: UserRepository,
        private val navigator: Navigator,
        private val selectedJournalsProvider: SelectedJournalsProvider,
        private val utilsWrapper: UtilsWrapper,
        private val analyticsTracker: AnalyticsTracker,
        private val mainActivityLauncher: MainActivityLauncher,
        private val editorLauncher: EditorLauncher,
        private val activityEventHandler: ActivityEventHandler,
    ) : ViewModel() {
        val uiState =
            combine(
                entryRepository.liveEntryCount().distinctUntilChanged(),
                entryRepository.liveEntryCountForDate().distinctUntilChanged(),
                journalRepository
                    .getAllJournalsLive(false)
                    .map { journals ->
                        journals.map { journal -> journal.isHideStreaksEnabled }
                    }.distinctUntilChanged(),
            ) { _, _, _ ->
                val streakDays = streaksCalculator.calculateStreakWithSharedJournals()
                val journals = getStreakJournals()
                val streakWeekDays = getStreakWeekDays()

                UiState.Streaks(
                    streakDays = streakDays,
                    streakWeekDays = streakWeekDays,
                    journals = journals,
                )
            }.stateIn(viewModelScope, SharingStarted.Lazily, UiState.Loading)

        private val _journalOptionsState = MutableStateFlow<JournalOptionsState?>(null)
        val journalOptionsState = _journalOptionsState.asStateFlow()

        private val dayOfWeekList: DaysOfWeekList = DaysOfWeekList(timeProvider.getFirstDayOfWeek())

        fun shareStreaks(
            bitmap: Bitmap,
            context: Context,
        ) {
            viewModelScope.launch(databaseDispatcher) {
                analyticsTracker.trackButtonTapped("streakView_share")
                val streaksFile: File = utilsWrapper.saveBitmapToFile(context, bitmap, "streaks_file")
                utilsWrapper.shareImage(context, streaksFile.absolutePath)
            }
        }

        fun close() {
            viewModelScope.launch {
                analyticsTracker.trackButtonTapped("streakView_close")
                navigator.goBack()
            }
        }

        fun showJournalOptions(
            journalId: Int,
            journalName: String,
        ) {
            viewModelScope.launch {
                analyticsTracker.trackButtonTapped("streakView_journal")
                _journalOptionsState.value = JournalOptionsState(journalId, journalName)
            }
        }

        fun openJournal(journalId: Int) {
            viewModelScope.launch {
                _journalOptionsState.value = null

                analyticsTracker.trackButtonTapped("streakView_journalMenu_openJournal")

                activityEventHandler.sendEvent(
                    OpenJournalOnTimeline(
                        journalId = journalId,
                        selectedJournalsProvider = selectedJournalsProvider,
                        mainActivityLauncher = mainActivityLauncher,
                    ),
                )
            }
        }

        fun createEntry(journalId: Int) {
            viewModelScope.launch {
                _journalOptionsState.value = null

                analyticsTracker.trackButtonTapped("streakView_journalMenu_createEntry")

                val newEntry =
                    entryRepository.createNewEntry(
                        journalId = journalId,
                    )
                val newEntryInformation =
                    EditorLauncher.NewEntryInformation(
                        AnalyticsTracker.NewEntrySource.STREAKS,
                        InitialContent.BLANK,
                    )
                editorLauncher.editNewEntry(
                    entry = newEntry,
                    newEntryInformation = newEntryInformation,
                    navigateTo = navigator::navigateTo,
                )
            }
        }

        fun closeJournalOptions() {
            _journalOptionsState.value = null
        }

        private suspend fun getStreakWeekDays(): List<StreakWeekDay> {
            val week = mutableListOf<StreakWeekDay>()
            // First day of the week can vary based on the user's locale. Generally, SUNDAY is the default in countries
            // influenced by the US, MONDAY is standard in most of Europe and Asia, and SATURDAY can be common in some
            // Middle Eastern countries due to the weekend structure.
            val firstDayOfWeek = timeProvider.getFirstDayOfWeek()
            if (firstDayOfWeek == Calendar.SATURDAY) {
                week.add(getStreakWeekDay(DayOfWeek.SATURDAY))
            }
            if (firstDayOfWeek == Calendar.SUNDAY || firstDayOfWeek == Calendar.SATURDAY) {
                week.add(getStreakWeekDay(DayOfWeek.SUNDAY))
            }
            week.add(getStreakWeekDay(DayOfWeek.MONDAY))
            week.add(getStreakWeekDay(DayOfWeek.TUESDAY))
            week.add(getStreakWeekDay(DayOfWeek.WEDNESDAY))
            week.add(getStreakWeekDay(DayOfWeek.THURSDAY))
            week.add(getStreakWeekDay(DayOfWeek.FRIDAY))
            if (firstDayOfWeek != Calendar.SATURDAY) {
                week.add(getStreakWeekDay(DayOfWeek.SATURDAY))
            }
            if (firstDayOfWeek != Calendar.SUNDAY && firstDayOfWeek != Calendar.SATURDAY) {
                week.add(getStreakWeekDay(DayOfWeek.SUNDAY))
            }

            return week
        }

        @VisibleForTesting
        suspend fun getStreakWeekDay(dayOfWeek: DayOfWeek): StreakWeekDay {
            val currentDate = timeProvider.currentLocalDate()
            val daysToDayOfWeek =
                dayOfWeekList.daysToPreviousDay(
                    currentDay = currentDate.dayOfWeek,
                    previousDay = dayOfWeek,
                )
            // Go to the previous date based on [dateOfWeek] and current date.
            val currentDateForDayOfWeek = currentDate.minusDays(daysToDayOfWeek.daysToPreviousDay.toLong())
            // From that date, go back DAYS_MINUS_WEEK * 7 days to cover DAYS_MINUS_WEEK (18) instances of the [dayOfWeek].
            // For example,if [dayOfWeek] is MONDAY and current date is 2024-10-8 (a TUESDAY), then [daysToDayOfWeek] is 1
            // and [currentDateForDayOfWeek] is 2024-10-7 and since becomes 2024-6-7 which represents the 18th MONDAY from
            // the current date.
            val previousWeeks = if (daysToDayOfWeek.wasInPreviousWeek) DAYS_MINUS_WEEK - 1 else DAYS_MINUS_WEEK
            val since = currentDateForDayOfWeek.minusDays(previousWeeks * 7)
            // Generates a sequences of dates that represents the [dayOfWeek] for the previous 18 weeks. For the previous
            // example, represent dates for each MONDAY from 2024-6-7 to 2024-10-7.
            val dateRange: Sequence<LocalDate> =
                generateSequence(since) { date ->
                    if (date < currentDateForDayOfWeek) date.plusDays(7) else null
                }
            // We query all the dates with entries since 2024-6-7 and check if the [dayOfWeek] for each week has an entry.
            val userId = userRepository.getUser()?.id
            val datesWithEntries = streakRepository.getDatesThatHaveEntriesSince(since, userId)
            val days =
                dateRange
                    .map { date ->
                        DayJournaled(datesWithEntries.contains(date))
                    }.toMutableList()
                    .also {
                        if (daysToDayOfWeek.wasInPreviousWeek) {
                            it.add(DayJournaled(null))
                        }
                    }

            return StreakWeekDay(dayOfWeek = dayOfWeek, days = days)
        }

        @VisibleForTesting
        suspend fun getStreakJournals(): List<StreakJournal> {
            val currentDate = timeProvider.currentLocalDate()
            val since = currentDate.minusDays(DAYS_MINUS_JOURNAL)
            val dateRange: Sequence<LocalDate> =
                generateSequence(since) { date ->
                    if (date < currentDate) date.plusDays(1) else null
                }
            return journalRepository
                .getAllJournals(includeHidden = true)
                .filter {
                    !it.isHideFromStreakEnabledNonNull() && !it.isPlaceholderForEncryptedJournalNonNull()
                }.sortedBy { it.sortOrder ?: 0 }
                .map { journal ->
                    val datesWithEntries =
                        if (journal.isShared == true) {
                            streakRepository.getDatesThatHaveEntriesSinceForSharedJournal(
                                journalId = journal.id,
                                since = since,
                                userId = userRepository.getUser()?.id ?: "",
                            )
                        } else {
                            streakRepository.getDatesThatHaveEntriesSinceForJournal(journalId = journal.id, since = since)
                        }
                    val days =
                        dateRange
                            .map { date ->
                                DayJournaled(datesWithEntries.contains(date))
                            }.toList()
                    val entriesToday =
                        if (journal.isShared == true) {
                            streakRepository.getNumEntriesForSharedJournalOnDate(
                                journalId = journal.id,
                                date = currentDate,
                                userId = userRepository.getUser()?.id ?: "",
                            )
                        } else {
                            streakRepository.getNumEntriesOnDate(journalId = journal.id, date = currentDate)
                        }

                    StreakJournal(
                        journalId = journal.id,
                        journalName = journal.name ?: "",
                        entriesToday = entriesToday,
                        color = journal.journalColor.backgroundColorRes,
                        days = days,
                    )
                }
        }

        companion object {
            private const val DAYS_MINUS_JOURNAL = 18L
            private const val DAYS_MINUS_WEEK = 17L
        }

        sealed interface UiState {
            data object Loading : UiState

            data class Streaks(
                val streakDays: Int,
                val streakWeekDays: List<StreakWeekDay>,
                val journals: List<StreakJournal>,
            ) : UiState
        }

        class JournalOptionsState(
            val journalId: Int,
            val journalName: String,
        )
    }

data class StreakWeekDay(
    val dayOfWeek: DayOfWeek,
    val days: List<DayJournaled>,
)

@JvmInline
value class DayJournaled(
    val isFilled: Boolean?,
)

data class StreakJournal(
    val journalId: Int,
    val journalName: String,
    val entriesToday: Int,
    @ColorRes
    val color: Int,
    val days: List<DayJournaled>,
)

private class DaysOfWeekList(
    private val firstDayOfWeek: Int,
) {
    private val days =
        buildList {
            if (firstDayOfWeek == Calendar.SATURDAY) {
                add(DayOfWeek.SATURDAY)
            }
            if (firstDayOfWeek == Calendar.SUNDAY || firstDayOfWeek == Calendar.SATURDAY) {
                add(DayOfWeek.SUNDAY)
            }
            add(DayOfWeek.MONDAY)
            add(DayOfWeek.TUESDAY)
            add(DayOfWeek.WEDNESDAY)
            add(DayOfWeek.THURSDAY)
            add(DayOfWeek.FRIDAY)
            if (firstDayOfWeek != Calendar.SATURDAY) {
                add(DayOfWeek.SATURDAY)
            }
            if (firstDayOfWeek != Calendar.SUNDAY && firstDayOfWeek != Calendar.SATURDAY) {
                add(DayOfWeek.SUNDAY)
            }
        }

    /**
     * Return the number of days between the current day of the week and the previous day of the week.
     *
     * Example: If the current day of the week is MONDAY and the previous day of the week is FRIDAY, then it would
     * return 3 because we have to go through SUNDAY, SATURDAY to FRIDAY.
     *
     * @param currentDay The current day of the week.
     * @param previousDay The previous day of the week.
     * @return Number of days between the current day of the week and the previous day of the week.
     */
    fun daysToPreviousDay(
        currentDay: DayOfWeek,
        previousDay: DayOfWeek,
    ): PreviousDays {
        if (currentDay == previousDay) {
            return PreviousDays(0, false)
        }
        var indexCurrentDay = days.indexOf(currentDay)
        var daysToPreviousDay = 0
        var wasInPreviousWeek = false
        while (true) {
            indexCurrentDay -= 1
            if (indexCurrentDay < 0) {
                wasInPreviousWeek = true
                indexCurrentDay = days.size - 1
            }
            daysToPreviousDay += 1

            if (days[indexCurrentDay] == previousDay) {
                break
            }
        }

        return PreviousDays(daysToPreviousDay, wasInPreviousWeek)
    }

    class PreviousDays(
        val daysToPreviousDay: Int,
        val wasInPreviousWeek: Boolean,
    )
}
