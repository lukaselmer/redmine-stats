now = DateTime.now
@start_date = now - now.wday.days
@end_date = @start_date + 7.days

ignore_issues = [3646]

def hours_by_issue(issue, sum_all = false)
  e = issue.time_entries
  e = e.where(spent_on: @start_date..@end_date) unless sum_all
  e.map(&:hours).sum.round(2)
end

def print_issue_list(name, arr, show_estimation = false)
  return if arr.empty?
  puts
  puts '=' * name.size
  puts name
  puts '=' * name.size
  sorted_naked_issues = arr.map{|v| [v[:issue].id, show_estimation ? v[:issue].estimated_hours : nil, hours_by_issue(v[:issue]), show_estimation ? hours_by_issue(v[:issue], true) : nil, v[:issue].subject]}.sort_by{|v| -v[2].to_f}

  estimated = sorted_naked_issues.map{|v| v[1].to_f}.sum.round(2)
  week = sorted_naked_issues.map{|v| v[2].to_f}.sum.round(2)
  total = sorted_naked_issues.map{|v| v[3].to_f}.sum.round(2)
  puts "Total hours (this week): estimated: #{estimated}, this week: #{week}, total: #{total}, precision: #{total - estimated}"
  puts "#       #{'estim. ' if show_estimation} spent   #{'totsp. ' if show_estimation} subject"
  sorted_naked_issues.map!{|v| v.map{|vv| vv.is_a?(Numeric) || vv.nil? ? ("%-7s" % vv) : vv}}
  puts sorted_naked_issues.map{|v| v.join(' ')}.join("\n")
  print_bulk_edit(arr)
end

def print_bulk_edit(arr)
  puts "https://redmine.renuo.ch/issues/bulk_edit?#{ arr.map{|v| v[:issue].id}.sort.map{|v| "ids%5B%5D=#{v}"}.join('&') }"
end

entries_without_issues = TimeEntry.where(spent_on: @start_date..@end_date).to_a.select{|t| !t.issue}
unless entries_without_issues.empty?
  p entries_without_issues
  fail 'time entries without issues found!'
end

issues_this_week = TimeEntry.where(spent_on: @start_date..@end_date).includes(:issue).map(&:issue).uniq.reject{|i| i.nil? || ignore_issues.include?(i.id)}
ongoing = IssueCustomField.find(8)
sprint = IssueCustomField.find(7)
backlog_priority = IssueCustomField.find(5)
# issues_this_week.map{|v| v.custom_field_value(sprint) }
issues_this_week_enhanced = issues_this_week.map{|v| {ongoing: v.custom_field_value(ongoing) == '1', sprint: v.custom_field_value(sprint).try(:to_date), issue: v, tracker_name: v.tracker.name} }
ongoing_issues = issues_this_week_enhanced.select{|v| v[:ongoing]}
normal_issues = issues_this_week_enhanced.select{|v| !v[:ongoing]}

all_planned_issues = normal_issues.select{|v| !%w(Action Support).include?(v[:tracker_name])}
planned_issues_without_sprint = all_planned_issues.select{|v| v[:sprint].nil?}
planned_issues = (all_planned_issues - planned_issues_without_sprint).select{|v| @start_date <= v[:sprint] && v[:sprint] <= @end_date }
wrong_sprint_issues = all_planned_issues - planned_issues - planned_issues_without_sprint

all_action_issues = normal_issues.select{|v| v[:tracker_name] == 'Action'}
action_issues = all_action_issues.select{|v| !v[:sprint].nil? && @start_date <= v[:sprint] && v[:sprint] <= @end_date }
wrong_action_issues = all_action_issues - action_issues

all_support_issues = normal_issues.select{|v| v[:tracker_name] == 'Support'}
support_issues = all_support_issues.select{|v| !v[:sprint].nil? && @start_date <= v[:sprint] && v[:sprint] <= @end_date }
wrong_support_issues = all_support_issues - support_issues

print_issue_list('Ongoing Issues', ongoing_issues)
print_issue_list('Support', support_issues)
print_issue_list('Support Issues in the Wrong Sprint (this should be empty)', wrong_support_issues)
print_issue_list('Action', action_issues, true)
print_issue_list('Action Issues in the Wrong Sprint (this should always be empty)!?', wrong_action_issues)
print_issue_list('Planned Issues', planned_issues, true)
print_issue_list('Issues Without a Sprint (this should be empty unless it\'s only an estimation)', planned_issues_without_sprint)
print_issue_list('Issues in the Wrong Sprint (this should be empty unless it\'s only an estimation)', wrong_sprint_issues)
