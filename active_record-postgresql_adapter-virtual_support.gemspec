lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name          = 'active_record-postgresql_adapter-virtual_support'
  spec.version       = '1.0.0'
  spec.authors       = ['Ryunosuke Sato']
  spec.email         = ['tricknotes.rs@gmail.com']

  spec.summary       = %q{Backport gem for rails/rails#41856 into Rails 6.1.}
  spec.description   = %q{Backport gem for rails/rails#41856 into Rails 6.1.}
  spec.homepage      = 'https://github.com/tricknotes/active_record-postgresql_adapter-virtual_support'
  spec.license       = 'MIT'

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency 'activerecord', '~> 6.1.0'
end
