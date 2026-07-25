class DestinationsController < ApplicationController
  before_action :require_project_access
  before_action :require_project_editor, except: %i[index show]

  def index
    @destinations = Current.project.destinations.order(created_at: :desc)
  end

  def show
    @destination = Current.project.destinations.find(params[:id])
  end

  def new
    @destination = Current.project.destinations.new
  end

  def create
    @destination = Current.project.destinations.new(destination_params)
    if @destination.save
      redirect_to @destination, notice: "Destination created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @destination = Current.project.destinations.find(params[:id])
  end

  def update
    @destination = Current.project.destinations.find(params[:id])
    if @destination.update(destination_params)
      redirect_to @destination, notice: "Destination updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @destination = Current.project.destinations.find(params[:id])
    @destination.destroy
    redirect_to destinations_path, notice: "Destination deleted."
  end

  def rotate_secret
    @destination = Current.project.destinations.find(params[:id])
    @destination.regenerate_signing_secret
    redirect_to @destination, notice: "Signing secret rotated. New forwards use the new secret."
  end

  private

  def destination_params
    permitted = params.require(:destination).permit(:name, :url, :rate_limit, :rate_limit_period)
    permitted.merge(headers: parse_headers(params.dig(:destination, :headers_text)))
  end

  # ponytail: one "Key: Value" per line, split on the first colon; blank/keyless lines dropped.
  def parse_headers(text)
    text.to_s.lines.each_with_object({}) do |line, acc|
      key, sep, value = line.partition(":")
      next if sep.empty?
      key = key.strip
      acc[key] = value.strip unless key.empty?
    end
  end
end
