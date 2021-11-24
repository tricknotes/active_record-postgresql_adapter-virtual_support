# This is a monley patch for https://github.com/rails/rails/pull/41856

require 'active_record/connection_adapters/postgresql_adapter'

raise ArgumentError, "This patch should be removed in rails (#{Rails.gem_version})" if  Rails.gem_version >= Gem::Version.new(7)

module ActiveRecord
  module ConnectionAdapters
    module DatabaseStatements
      private

      def build_fixture_sql(fixtures, table_name)
        columns = schema_cache.columns_hash(table_name).reject { |_, column| supports_virtual_columns? && column.virtual? }

        values_list = fixtures.map do |fixture|
          fixture = fixture.stringify_keys

          unknown_columns = fixture.keys - columns.keys
          if unknown_columns.any?
            raise Fixture::FixtureError, %(table "#{table_name}" has no columns named #{unknown_columns.map(&:inspect).join(', ')}.)
          end

          columns.map do |name, column|
            if fixture.key?(name)
              type = lookup_cast_type_from_column(column)
              with_yaml_fallback(type.serialize(fixture[name]))
            else
              default_insert_value(column)
            end
          end
        end

        table = Arel::Table.new(table_name)
        manager = Arel::InsertManager.new
        manager.into(table)

        if values_list.size == 1
          values = values_list.shift
          new_values = []
          columns.each_key.with_index { |column, i|
            unless values[i].equal?(DEFAULT_INSERT_VALUE)
              new_values << values[i]
              manager.columns << table[column]
            end
          }
          values_list << new_values
        else
          columns.each_key { |column| manager.columns << table[column] }
        end

        manager.values = manager.create_values_list(values_list)
        visitor.compile(manager.ast)
      end

    end

    module PostgreSQL
      class Column
        def initialize(*, serial: nil, generated: nil, **)
          super
          @serial = serial
          @generated = generated
        end

        def virtual?
          # We assume every generated column is virtual, no matter the concrete type
          @generated.present?
        end

        def has_default?
          super && !virtual?
        end
      end

      class SchemaCreation
        private

        def add_column_options!(sql, options)
          if options[:collation]
            sql << " COLLATE \"#{options[:collation]}\""
          end

          if as = options[:as]
            sql << " GENERATED ALWAYS AS (#{as})"

            if options[:stored]
              sql << " STORED"
            else
              raise ArgumentError, <<~MSG
                  PostgreSQL currently does not support VIRTUAL (not persisted) generated columns.
                  Specify 'stored: true' option for '#{options[:column].name}'
              MSG
            end
          end
          super
        end
      end

      class TableDefinition

        def new_column_definition(name, type, **options) # :nodoc:
          case type
          when :virtual
            type = options[:type]
          end

          super
        end
      end

      class SchemaDumper
        private

        def prepare_column_options(column)
          spec = super
          spec[:array] = "true" if column.array?

          if @connection.supports_virtual_columns? && column.virtual?
            spec[:as] = extract_expression_for_virtual_column(column)
            spec[:stored] = true
            spec = { type: schema_type(column).inspect }.merge!(spec)
          end

          spec
        end

        def extract_expression_for_virtual_column(column)
          column.default_function.inspect
        end
      end

      module SchemaStatements
        private

        def new_column_from_field(table_name, field)
          column_name, type, default, notnull, oid, fmod, collation, comment, attgenerated = field
          type_metadata = fetch_type_metadata(column_name, type, oid.to_i, fmod.to_i)
          default_value = extract_value_from_default(default)
          default_function = extract_default_function(default_value, default)

          if match = default_function&.match(/\Anextval\('"?(?<sequence_name>.+_(?<suffix>seq\d*))"?'::regclass\)\z/)
            serial = sequence_name_from_parts(table_name, column_name, match[:suffix]) == match[:sequence_name]
          end

          PostgreSQL::Column.new(
            column_name,
            default_value,
            type_metadata,
            !notnull,
            default_function,
            collation: collation,
            comment: comment.presence,
            serial: serial,
            generated: attgenerated
          )
        end
      end
    end

    class PostgreSQLAdapter
      def supports_virtual_columns?
        database_version >= 120_000 # >= 12.0
      end

      def column_definitions(table_name)
        query(<<~SQL, "SCHEMA")
              SELECT a.attname, format_type(a.atttypid, a.atttypmod),
                     pg_get_expr(d.adbin, d.adrelid), a.attnotnull, a.atttypid, a.atttypmod,
                     c.collname, col_description(a.attrelid, a.attnum) AS comment,
                     #{supports_virtual_columns? ? 'attgenerated' : quote('')} as attgenerated
                FROM pg_attribute a
                LEFT JOIN pg_attrdef d ON a.attrelid = d.adrelid AND a.attnum = d.adnum
                LEFT JOIN pg_type t ON a.atttypid = t.oid
                LEFT JOIN pg_collation c ON a.attcollation = c.oid AND a.attcollation <> t.typcollation
               WHERE a.attrelid = #{quote(quote_table_name(table_name))}::regclass
                 AND a.attnum > 0 AND NOT a.attisdropped
               ORDER BY a.attnum
        SQL
      end
    end
  end
end
