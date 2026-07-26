class SourcesController < ApplicationController
  before_action :require_project_access
  before_action :require_project_editor, except: %i[index show]

  def index
    @sources = Current.project.sources.order(created_at: :desc)
  end

  def show
    @source = Current.project.sources.find(params[:id])
  end

  # An unknown ?provider= is ignored rather than rejected: the picker is the
  # fallback, so a stale link just lands back on it.
  def new
    provider = params[:provider].presence_in(Source::VERIFICATION_PRESETS.keys)
    @source = Current.project.sources.new(verification_provider: provider, name: Source.provider_name(provider))
  end

  def create
    @source = Current.project.sources.new(source_params)
    if @source.save
      redirect_to @source, notice: "Source created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @source = Current.project.sources.find(params[:id])
  end

  def update
    @source = Current.project.sources.find(params[:id])
    if @source.update(source_params)
      redirect_to @source, notice: "Source updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @source = Current.project.sources.find(params[:id])
    @source.destroy
    redirect_to sources_path, notice: "Source deleted."
  end

  def rotate_token
    @source = Current.project.sources.find(params[:id])
    @source.regenerate_token
    redirect_to @source, notice: "Ingest token rotated. The old URL no longer works."
  end

  private

  def source_params
    params.require(:source).permit(
      :name,
      :verification_provider, :verification_secret, :verification_header, :verification_algorithm, :verification_encoding,
      :verification_header_format, :verification_signature_prefix, :verification_signature_key,
      :verification_timestamp_key, :verification_timestamp_header, :verification_payload_template,
      :verification_tolerance_seconds,
      :dedupe_window, :dedupe_key
    )
  end
end
