# Arquivo do sistema, ligado a cliente, contrato, projeto, proposta ou fornecedor (RF 37).
# Upload pelo Active Storage (S3 em produção). "Enviado por" e data são automáticos.
class Document < ApplicationRecord
  include Auditable
  include LabeledEnums

  LINKABLE_TYPES = %w[Company Contract].freeze # Projeto, proposta e fornecedor entram nas próximas fases
  MAX_SIZE = 25.megabytes

  audited area: "documentos"
  labeled_enum :kind, contract: "Contrato", proposal: "Proposta", invoice: "Nota", briefing: "Briefing",
                      technical: "Documento técnico", other: "Outro"

  belongs_to :documentable, polymorphic: true
  belongs_to :company, optional: true
  belongs_to :uploaded_by, class_name: "User"
  has_one_attached :file

  validates :title, presence: true
  validates :documentable_type, inclusion: { in: LINKABLE_TYPES }
  validate :file_attached

  before_validation :set_company_from_link
  before_validation :set_title_from_file

  scope :recent, -> { order(created_at: :desc) }

  def activity_name
    "o documento #{title}"
  end

  def to_s
    title
  end

  private

  def set_company_from_link
    self.company = documentable.is_a?(Company) ? documentable : documentable.try(:company) || company
  end

  def set_title_from_file
    self.title = file.filename.to_s if title.blank? && file.attached?
  end

  def file_attached
    if !file.attached?
      errors.add(:file, "precisa ser enviado")
    elsif file.blob.byte_size > MAX_SIZE
      errors.add(:file, "passa do limite de 25 MB")
    end
  end
end
