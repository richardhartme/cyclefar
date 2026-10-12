module TrainingPlansHelper
  def plan_field_aria(*attributes, help: nil)
    invalid_attributes = attributes.select { |attribute| @configuration.errors[attribute].any? }
    { invalid: invalid_attributes.any? ? true : nil,
      describedby: [ help, *invalid_attributes.map { |attribute| "#{attribute}-errors" } ].compact.join(" ").presence }
  end

  def plan_select_options(options, selected)
    choices = options.dup
    if selected.present? && choices.none? { |_label, value| value.to_s == selected.to_s }
      choices << [ "Invalid choice (#{selected})", selected ]
    end
    options_for_select(choices, selected)
  end
end
