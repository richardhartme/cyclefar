class PlannedWorkoutsController < ApplicationController
  before_action :load_workout, except: %i[new create]

  def new
    @plan = Current.user.training_plans.active.sole
    @scheduled_on = Date.iso8601(params.require(:scheduled_on))
    Workouts::Creator.new(@plan).validate_destination!(@scheduled_on)
  rescue Date::Error, ArgumentError => error
    redirect_to root_path, alert: error.message
  end

  def create
    plan = Current.user.training_plans.active.sole
    workout = Workouts::Creator.new(plan).create!(
      scheduled_on: Date.iso8601(params.require(:scheduled_on)),
      subtype: params.require(:subtype),
      duration_minutes: params.require(:duration_minutes))
    redirect_to root_path, notice: "#{workout.name} added to #{workout.scheduled_on.to_fs(:long)}."
  rescue Date::Error, ArgumentError, ActiveRecord::RecordInvalid => error
    redirect_to root_path, alert: error.message
  end

  def show
    @material_change_proposal = material_change_proposal
  end

  def shuffle
    result = Workouts::ManualEditor.new(@workout).apply!(action: params.require(:action_kind))
    redirect_to planned_workout_path(@workout), notice: result.material_change ? "Workout updated. This is a material change; the rest of the plan is unchanged." : "Workout updated."
  rescue ArgumentError, ActiveRecord::RecordInvalid => error
    redirect_to planned_workout_path(@workout), alert: error.message
  end

  def change
    proposal = nil
    PlannedWorkout.transaction do
      result = Workouts::ManualEditor.new(@workout).apply!(action: :change, subtype: params.require(:subtype), duration_minutes: params.require(:duration_minutes))
      proposal = Planning::MaterialChangeProposal.new(@workout).replace!(material_change: result.material_change)
    end
    redirect_to planned_workout_path(@workout), notice: proposal ? "Workout changed. Review the optional upcoming replan below." : "Workout changed."
  rescue ArgumentError, ActiveRecord::RecordInvalid => error
    redirect_to planned_workout_path(@workout), alert: error.message
  end

  def move
    raise ArgumentError, "Completed workouts cannot be moved" unless @workout.planned?

    destination = Date.iso8601(params.require(:scheduled_on))
    raise ArgumentError, "Choose an empty date inside this plan" unless destination.between?(@workout.training_plan.starts_on, @workout.training_plan.ends_on)
    raise ArgumentError, "That date already has a workout" if @workout.training_plan.planned_workouts.where(scheduled_on: destination).where.not(id: @workout.id).exists?

    phase = @workout.training_plan.plan_phases.find { |item| destination.between?(item.starts_on, item.ends_on) }
    @workout.update!(scheduled_on: destination, plan_phase: phase)
    redirect_to root_path, notice: "Workout moved to #{destination.to_fs(:long)}."
  rescue Date::Error, ArgumentError, ActiveRecord::RecordInvalid => error
    redirect_to planned_workout_path(@workout), alert: error.message
  end

  def copy
    destination = Date.iso8601(params.require(:scheduled_on))
    copy = Workouts::Copier.new(@workout).copy_to!(destination: destination)
    redirect_to root_path, notice: "Workout copied to #{copy.scheduled_on.to_fs(:long)}."
  rescue Date::Error, ArgumentError, ActiveRecord::RecordInvalid => error
    redirect_to planned_workout_path(@workout), alert: error.message
  end

  def complete
    proposal = Adaptations::CompletionRecorder.new(workout: @workout, rpe: params.require(:rpe), completion_quality: params.require(:completion_quality)).call
    redirect_to root_path, notice: proposal ? "Workout completed. An adaptation proposal is ready for review." : "Workout completed."
  rescue ArgumentError, ActiveRecord::RecordInvalid => error
    redirect_to planned_workout_path(@workout), alert: error.message
  end

  def complete_test
    raise ArgumentError, "Only a planned FTP test can be marked done" unless @workout.planned? && @workout.ftp_test?

    @workout.update!(status: :completed, completed_at: Time.current)
    redirect_to settings_path, notice: "FTP test recorded. Update your current FTP from the result."
  rescue ArgumentError, ActiveRecord::RecordInvalid => error
    redirect_to planned_workout_path(@workout), alert: error.message
  end

  def miss
    Planning::MissedWorkoutResolver.new(@workout).resolve!(mode: params.require(:resolution), destination: params[:scheduled_on])
    redirect_to root_path, notice: "Missed workout resolved."
  rescue Date::Error, ArgumentError, ActiveRecord::RecordInvalid => error
    redirect_to planned_workout_path(@workout), alert: error.message
  end

  private

  def load_workout
    @workout = PlannedWorkout.includes(:workout_steps, :plan_phase, training_plan: :plan_phases).find(params[:id])
  end

  def material_change_proposal
    @workout.training_plan.adaptation_proposals.find do |proposal|
      proposal.material_change_replan? && proposal.source_workout_id == @workout.id
    end
  end
end
