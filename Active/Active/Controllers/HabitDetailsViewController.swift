//
//  HabitDetailsViewController.swift
//  Active
//
//  Created by Tiago Maia Lopes on 02/07/18.
//  Copyright © 2018 Tiago Maia Lopes. All rights reserved.
//

import UIKit
import CoreData
import JTAppleCalendar

class HabitDetailsViewController: UIViewController {

    // MARK: Properties

    /// The habit presented by this controller.
    var habit: HabitMO! {
        didSet {
            habitColor = HabitMO.Color(rawValue: habit.color)?.getColor()
        }
    }

    /// The current habit's color.
    private var habitColor: UIColor!

    /// The habit's ordered challenge entities to be displayed.
    /// - Note: This array mustn't be empty. The existence of challenges is ensured
    ///         in the habit's creation and edition process.
    private var challenges: [DaysChallengeMO]! {
        didSet {
            // Store the initial and final calendar dates.
            startDate = challenges.first!.fromDate!.getBeginningOfMonth()!
            finalDate = challenges.last!.toDate!
        }
    }

    /// The initial calendar date.
    internal var startDate: Date!

    /// The final calendar date.
    internal var finalDate: Date!

    /// The habit storage used to manage the controller's habit.
    var habitStorage: HabitStorage!

    /// The persistent container used by this store to manage the
    /// provided habit.
    var container: NSPersistentContainer!

    //    /// View holding the prompt to ask the user if the activity
//    /// was executed in the current day.
//    @IBOutlet weak var promptView: UIView!

    /// The cell's reusable identifier.
    internal let cellIdentifier = "Habit day cell id"

    /// The calendar view showing the habit days.
    /// - Note: The collection view will show a range with
    ///         the Habit's first days until the last ones.
    @IBOutlet weak var calendarView: JTAppleCalendarView!

    /// The month header view, with the month label and next/prev buttons.
    @IBOutlet weak var monthHeaderView: MonthHeaderView! {
        didSet {
            monthTitleLabel = monthHeaderView.monthLabel
            nextMonthButton = monthHeaderView.nextButton
            previousMonthButton = monthHeaderView.previousButton
        }
    }

    /// The month title label in the calendar's header.
    internal weak var monthTitleLabel: UILabel!

    /// The next month header button.
    internal weak var nextMonthButton: UIButton! {
        didSet {
            nextMonthButton.addTarget(self, action: #selector(goNext), for: .touchUpInside)
        }
    }

    /// The previous month header button.
    internal weak var previousMonthButton: UIButton! {
        didSet {
            previousMonthButton.addTarget(self, action: #selector(goPrevious), for: .touchUpInside)
        }
    }

    /// The view holding the prompt for the current day.
    /// - Note: This view is only displayed if today is a challenge day to be accounted.
    @IBOutlet weak var promptContentView: UIView!

    /// The title displaying what challenge's day is today.
    @IBOutlet weak var currentDayTitleLabel: UILabel!

    /// The switch the user uses to mark the current habit's day as executed.
    @IBOutlet weak var wasExecutedSwitch: UISwitch!

    /// The supporting label informing the user that the activity was executed.
    @IBOutlet weak var promptAnswerLabel: UILabel!

    // MARK: ViewController Life Cycle

    override func viewDidLoad() {
        super.viewDidLoad()

        checkDependencies()
        // Get the habit's challenges to display in the calendar.
        challenges = getChallenges(from: habit)

        // Configure the calendar.
        calendarView.calendarDataSource = self
        calendarView.calendarDelegate = self

        title = habit.name
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Show the current date in the calendar.
        let today = Date().getBeginningOfDay()
        calendarView.scrollToDate(today)

        // Configure the appearance of the prompt view.
        displayPromptView()
    }

    // MARK: Actions

    @IBAction func deleteHabit(_ sender: UIButton) {
        // Alert the user to see if the deletion is really wanted:

        // Declare the alert.
        let alert = UIAlertController(
            title: "Delete",
            message: """
Are you sure you want to delete this habit? Deleting this habit makes all the history \
information unavailable.
""",
            preferredStyle: .alert
        )
        // Declare its actions.
        alert.addAction(UIAlertAction(title: "delete", style: .destructive) { _ in
            // If so, delete the habit using the container's viewContext.
            // Pop the current controller.
            self.habitStorage.delete(
                self.habit, from:
                self.container.viewContext
            )
            self.navigationController?.popViewController(animated: true)
        })
        alert.addAction(UIAlertAction(title: "cancel", style: .default))

        // Present it.
        present(alert, animated: true)
    }

    /// Sets the current as executed or not, depending on the user's action.
    @IBAction func informActivityExecution(_ sender: UISwitch) {
        guard let challenge = habit.getCurrentChallenge(), let day = challenge.getCurrentDay() else {
            assertionFailure(
                "Inconsistency: There isn't a current habit day but the prompt is being displayed."
            )
            return
        }

        // Get the user's answer.
        let wasExecuted = sender.isOn

        day.managedObjectContext?.perform {
            day.wasExecuted = wasExecuted

            // TODO: Display an error to the user.
            try? day.managedObjectContext?.save()

            DispatchQueue.main.async {
                // Update the prompt view.
                self.displayPromptView()
                // Reload calendar to show the executed day.
                self.calendarView.reloadData()
            }
        }
    }

    /// Makes the calendar display the next month.
    @objc private func goNext() {
        goToNextMonth()
    }

    /// Makes the calendar display the previous month.
    @objc private func goPrevious() {
        goToPreviousMonth()
    }

    // MARK: Imperatives

    /// Asserts on the values of the main controller's dependencies.
    private func checkDependencies() {
        // Assert on the required properties to be injected
        // (habit, habitStorage, container and the calendar header views):
        assert(
            habit != nil,
            "Error: the needed habit wasn't injected."
        )
        assert(
            habitStorage != nil,
            "Error: the needed habitStorage wasn't injected."
        )
        assert(
            container != nil,
            "Error: the needed container wasn't injected."
        )
        assert(
            monthTitleLabel != nil,
            "Error: the month title label wasn't set."
        )
        assert(
            nextMonthButton != nil,
            "Error: the next month button wasn't set."
        )
        assert(
            previousMonthButton != nil,
            "Error: the previous month button wasn't set."
        )
    }

    /// Gets the challenges from the passed habit ordered by the fromDate property.
    /// - Returns: The habit's ordered challenges.
    private func getChallenges(from habit: HabitMO) -> [DaysChallengeMO] {
        // Declare and configure the fetch request.
        let request: NSFetchRequest<DaysChallengeMO> = DaysChallengeMO.fetchRequest()
        request.predicate = NSPredicate(format: "habit = %@", habit)
        request.sortDescriptors = [NSSortDescriptor(key: "fromDate", ascending: true)]

        // Fetch the results.
        let results = (try? container.viewContext.fetch(request)) ?? []

        // Assert on the values, the habit must have at least one challenge entity.
        assert(!results.isEmpty, "Inconsistency: A habit entity must always have at least one challenge entity.")

        return results
    }

    /// Gets the challenge matching a given date.
    /// - Note: The challenge is found if the date is in between or is it's begin or final.
    /// - Returns: The challenge entity, if any.
    private func getChallenge(from date: Date) -> DaysChallengeMO? {
        // Try to get the matching challenge by filtering through the habit's fetched ones.
        // The challenge matches when the passed date or is in between,
        // or is one of the challenge's limit dates (begin or end).
        return challenges.filter {
            date.isInBetween($0.fromDate!, $0.toDate!) || date == $0.fromDate! || date == $0.toDate!
        }.first
    }

    /// Displays the prompt view if today is a challenge's day.
    private func displayPromptView() {
        // ContentView is hidden by default.
        promptContentView.isHidden = true

        // Check if there's a current challenge for the habit.
        guard let currentChallenge = habit.getCurrentChallenge() else {
            return
        }
        // Check if today is a challenge's HabitDay.
        guard let currentDay = currentChallenge.getCurrentDay() else {
            return
        }

        // Get the order of the day in the challenge.
        guard let orderedChallengeDays = currentChallenge.days?.sortedArray(
            using: [NSSortDescriptor(key: "day.date", ascending: true)]
            ) as? [HabitDayMO] else {
                assertionFailure("Error: Couldn't get the challenge's sorted habit days.")
                return
        }
        guard let dayIndex = orderedChallengeDays.index(of: currentDay) else {
            assertionFailure("Error: Couldn't get the current day's index.")
            return
        }

        promptContentView.isHidden = false

        wasExecutedSwitch.onTintColor = habitColor

        let order = dayIndex + 1
        displayPromptViewTitle(withOrder: order)

        if currentDay.wasExecuted {
            wasExecutedSwitch.isOn = true
            promptAnswerLabel.text = "Yes, I did it."
            promptAnswerLabel.textColor = habitColor
        } else {
            wasExecutedSwitch.isOn = false
            promptAnswerLabel.text = "No, not yet."
            promptAnswerLabel.textColor = UIColor(red: 47/255, green: 54/255, blue: 64/255, alpha: 1)
        }
    }

    /// Configures the prompt view title text.
    /// - Parameter order: the order of day in the current challenge.
    private func displayPromptViewTitle(withOrder order: Int) {
        var orderTitle = ""

        switch order {
        case 1:
            orderTitle = "1st"
        case 2:
            orderTitle = "2nd"
        case 3:
            orderTitle = "3rd"
        default:
            orderTitle = "\(order)th"
        }

        let attributedString = NSMutableAttributedString(string: "\(orderTitle) day")
        attributedString.addAttributes(
            [
                NSAttributedStringKey.font: UIFont(name: "SFProText-Semibold", size: 20)!,
                NSAttributedStringKey.foregroundColor: habitColor
            ],
            range: NSRange(location: 0, length: orderTitle.count)
        )

        currentDayTitleLabel.attributedText = attributedString
    }
}

extension HabitDetailsViewController: CalendarDisplaying {

    // MARK: Imperatives

    /// Configures the appearance of a given cell when it's about to be displayed.
    /// - Parameters:
    ///     - cell: The cell being displayed.
    ///     - cellState: The cell's state.
    internal func handleAppearanceOfCell(
        _ cell: JTAppleCell,
        using cellState: CellState
    ) {
        // Cast it to the expected instance.
        guard let cell = cell as? CalendarDayCell else {
            assertionFailure("Couldn't cast the cell to a CalendarDayCell's instance.")
            return
        }

        if cellState.dateBelongsTo == .thisMonth {
            cell.dayTitleLabel.text = cellState.text

            // Try to get the matching challenge for the current date.
            if let challenge = getChallenge(from: cellState.date) {
                // Get the habitDay associated with the cell's date.
                guard let habitDay = challenge.getDay(for: cellState.date) else {
                    // If there isn't a day associated with the date, there's a bug.
                    assertionFailure("Inconsistency: a day should be returned from the challenge.")
                    return
                }

                // If there's a challenge, show cell as being part of it.
                let habitColor = HabitMO.Color(rawValue: habit.color)?.getColor()

                cell.backgroundColor = habitDay.wasExecuted ? habitColor : habitColor?.withAlphaComponent(0.5)
                cell.dayTitleLabel.textColor = .white

                if cellState.date.isInToday {
                    cell.circleView.backgroundColor = .white
                    cell.dayTitleLabel.textColor = UIColor(red: 74/255, green: 74/255, blue: 74/255, alpha: 1)
                } else if cellState.date.isFuture {
                    // Days to be completed in the future should have a less bright color.
                    cell.backgroundColor = cell.backgroundColor?.withAlphaComponent(0.3)
                }
            }
        } else {
            cell.dayTitleLabel.text = ""
            cell.backgroundColor = .white
        }
    }
}

extension HabitDetailsViewController: JTAppleCalendarViewDataSource, JTAppleCalendarViewDelegate {

    // MARK: JTAppleCalendarViewDataSource Methods

    func configureCalendar(_ calendar: JTAppleCalendarView) -> ConfigurationParameters {
        return ConfigurationParameters(
            startDate: startDate,
            endDate: finalDate
        )
    }

    // MARK: JTAppleCalendarViewDelegate Methods

    func calendar(
        _ calendar: JTAppleCalendarView,
        cellForItemAt date: Date,
        cellState: CellState,
        indexPath: IndexPath
    ) -> JTAppleCell {
        let cell = calendar.dequeueReusableJTAppleCell(
            withReuseIdentifier: cellIdentifier,
            for: indexPath
        )

        guard let dayCell = cell as? CalendarDayCell else {
            assertionFailure("Couldn't get the expected details calendar cell.")
            return cell
        }
        handleAppearanceOfCell(dayCell, using: cellState)

        return dayCell
    }

    func calendar(
        _ calendar: JTAppleCalendarView,
        willDisplay cell: JTAppleCell,
        forItemAt date: Date,
        cellState: CellState,
        indexPath: IndexPath
    ) {
        guard let dayCell = cell as? CalendarDayCell else {
            assertionFailure("Couldn't get the expected details calendar cell.")
            return
        }
        handleAppearanceOfCell(dayCell, using: cellState)
    }

    func calendar(
        _ calendar: JTAppleCalendarView,
        shouldSelectDate date: Date,
        cell: JTAppleCell?,
        cellState: CellState
    ) -> Bool {
        return false
    }
}
