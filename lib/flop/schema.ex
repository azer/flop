defprotocol Flop.Schema do
  @moduledoc """
  This protocol allows you to set query options in your Ecto schemas.

  ## Usage

  Derive `Flop.Schema` in your Ecto schema and set the filterable and sortable
  fields.

      defmodule Flop.Pet do
        use Ecto.Schema

        @derive {
          Flop.Schema,
          filterable: [:name, :species],
          sortable: [:name, :age]
        }

        schema "pets" do
          field :name, :string
          field :age, :integer
          field :species, :string
        end
      end


  After that, you can pass the module as the `:for` option to `Flop.validate/2`.

      iex> Flop.validate(%Flop{order_by: [:name]}, for: Flop.Pet)
      {:ok,
       %Flop{
         filters: [],
         limit: 50,
         offset: nil,
         order_by: [:name],
         order_directions: nil,
         page: nil,
         page_size: nil
       }}

      iex> {:error, %Flop.Meta{} = meta} = Flop.validate(
      ...>   %Flop{order_by: [:species]}, for: Flop.Pet
      ...> )
      iex> meta.params
      %{"order_by" => [:species], "filters" => []}
      iex> meta.errors
      [
        order_by: [
          {"has an invalid entry",
           [validation: :subset, enum: [:name, :age, :owner_name, :owner_age]]}
        ]
      ]

  ## Default and maximum limits

  To define a default or maximum limit, you can set the `default_limit` and
  `max_limit` option when deriving `Flop.Schema`. The maximum limit will be
  validated and the default limit applied by `Flop.validate/1`.

      @derive {
        Flop.Schema,
        filterable: [:name, :species],
        sortable: [:name, :age],
        max_limit: 100,
        default_limit: 50
      }

  ## Default sort order

  To define a default sort order, you can set the `default_order_by` and
  `default_order_directions` options when deriving `Flop.Schema`. The default
  values are applied by `Flop.validate/1`. If no order directions are set,
  `:asc` is assumed for all fields.

      @derive {
        Flop.Schema,
        filterable: [:name, :species],
        sortable: [:name, :age],
        default_order: %{
          order_by: [:name, :age],
          order_directions: [:asc, :desc]
        }
      }

  ## Restricting pagination types

  By default, `page`/`page_size`, `offset`/`limit` and cursor-based pagination
  (`first`/`after` and `last`/`before`) are enabled. If you want to restrict the
  pagination type for a schema, you can do that by setting the
  `pagination_types` option.

      @derive {
        Flop.Schema,
        filterable: [:name, :species],
        sortable: [:name, :age],
        pagination_types: [:first, :last]
      }

  See also `t:Flop.option/0` and `t:Flop.pagination_type/0`. Setting the value
  to `nil` allows all pagination types.

  ## Alias fields

  To sort by calculated values, you can use `Ecto.Query.API.selected_as/2` in
  your query, define an alias field in your schema, and add the alias field to
  the list of sortable fields.

  Schema:

      @derive {
        Flop.Schema,
        filterable: [],
        sortable: [:pet_count],
        alias_fields: [:pet_count]
      }

  Query:

      Owner
      |> join(:left, [o], p in assoc(o, :pets), as: :pets)
      |> group_by([o], o.id)
      |> select(
        [o, pets: p],
        {o.id, p.id |> count() |> selected_as(:pet_count)}
      )
      |> Flop.validate_and_run(params, for: Owner)

  Note that it is not possible to use field aliases in `WHERE` clauses, which
  means you cannot add alias fields to the list of filterable fields, and you
  cannot sort by an alias field if you are using cursor-based pagination.

  ## Compound fields

  Sometimes you might need to apply a search term to multiple fields at once,
  e.g. you might want to search in both the family name and given name field.
  You can do that with Flop by defining a compound field.

      @derive {
        Flop.Schema,
        filterable: [:full_name],
        sortable: [:full_name],
        compound_fields: [full_name: [:family_name, :given_name]]
      }

  This allows you to use the field name `:full_name` as any other field in the
  filter and order parameters.

  ### Filtering

      params = %{
        filters: [%{
          field: :full_name,
          op: :like,
          value: "margo"
        }]
      }

  This would translate to:

      WHERE family_name like '%margo%' OR given_name like '%margo%'

  Partial matches of the search term can be achieved with one of
  the like operators.

      params = %{
        filters: [%{
          field: :full_name,
          op: :ilike_and,
          value: ["margo", "martindale"]
        }]
      }
  or
      params = %{
        filters: [%{
          field: :full_name,
          op: :ilike_and,
          value: "margo martindale"
        }]
      }
  This would translate to:

      WHERE (family_name ilike '%margo%' OR given_name ilike '%margo%')
      AND (family_name ilike '%martindale%' OR given_name ilike '%martindale%')

  ### Filter operator rules

  - `:=~` `:like` `:not_like` `:like_and` `:like_or` `:ilike` `:not_ilike` `:ilike_and` `:ilike_or`  
    If a string value is passed it will be split at whitespace
    characters and each segment will be checked separately. If a list of strings is
    passed the individual strings are not split. The filter matches for a value
    if it matches for any of the fields.
  - `:empty`  
    Matches if all fields of the compound field are `nil`.
  - `:not_empty`  
    Matches if any field of the compound field is not `nil`.
  - `:==` `:!=` `:<=` `:<` `:>=` `:>` `:in` `:not_in` `:contains` `:not_contains`  
    ** These filter operators are ignored for compound fields at the moment.
    This will be added in a future version.**  
    The filter value is normalized by splitting the string at whitespaces and
    joining it with a space. The values of all fields of the compound field are
    split by whitespace character and joined with a space, and the resulting
    values are joined with a space again.

  ### Sorting

      params = %{
        order_by: [:full_name],
        order_directions: [:desc]
      }

  This would translate to:

      ORDER BY family_name DESC, given_name DESC

  Note that compound fields cannot be used as pagination cursors.

  ## Join fields

  If you need to filter or order across tables, you can define join fields.

  As an example, let's define these schemas:

      schema "owners" do
        field :name, :string
        field :email, :string

        has_many :pets, Pet
      end

      schema "pets" do
        field :name, :string
        field :species, :string

        belongs_to :owner, Owner
      end

  And now we want to find all owners that have pets of the species
  `"E. africanus"`. To do this, first we need to define a join field on the
  `Owner` schema.

      @derive {
        Flop.Schema,
        filterable: [:pet_species],
        sortable: [:pet_species],
        join_fields: [pet_species: [binding: :pets, field: :species]]
      }

  In this case, `:pet_species` would be the alias of the field that you can
  refer to in the filter and order parameters. The `:binding` option refers to
  the named binding you set with the `:as` option in the join statement of your
  query. `:field` is the field name on that binding.

  You can also set the `ecto_type` option, which allows Flop to determine which
  filter operators can be used on the field during the validation. This is also
  important if the field is a map or array field, so that Flop can check for
  empty arrays and empty maps when a `empty` or `not_empty` filter is used.

      @derive {
        Flop.Schema,
        filterable: [:pet_species],
        sortable: [:pet_species],
        join_fields: [
          pet_species: [
            binding: :pets,
            field: :species,
            ecto_type: :string
          ]
        ]
      }

  There is also a short syntax which you can use if you only want to specify
  the binding and the field:

      @derive {
        Flop.Schema,
        filterable: [:pet_species],
        sortable: [:pet_species],
        join_fields: [pet_species: {:pets, :species}]
      }

  In order to retrieve the pagination cursor value for a join field, Flop needs
  to know how to get the field value from the struct that is returned from the
  database. `Flop.Schema.get_field/2` is used for that. By default, Flop assumes
  that the binding name matches the name of the field for the association in
  your Ecto schema (the one you set with `has_one`, `has_many` or `belongs_to`).

  In the example above, Flop would try to access the field in the struct under
  the path `[:pets, :species]`.

  If you have joins across multiple tables, or if you can't give the binding
  the same name as the association field, you can specify the path explicitly.

      @derive {
        Flop.Schema,
        filterable: [:pet_species],
        sortable: [:pet_species],
        join_fields: [
          pet_species: [
            binding: :pets,
            field: :species,
            path: [:pets, :species]
        ]
      }

  After setting up the join fields, you can write a query like this:

      params = %{
        filters: [%{field: :pet_species, op: :==, value: "E. africanus"}]
      }

      Owner
      |> join(:left, [o], p in assoc(o, :pets), as: :pets)
      |> preload([pets: p], [pets: p])
      |> Flop.validate_and_run!(params, for: Owner)

  If your query returns data in a different format, you don't need to set the
  `:path` option. Instead, you can pass a custom cursor value function in the
  options. See `Flop.Cursor.get_cursors/2` and `t:Flop.option/0`.

  Note that Flop doesn't create the join clauses for you. The named bindings
  already have to be present in the query you pass to the Flop functions. You
  can use `Flop.with_named_bindings/4` or `Flop.named_bindings/3` to get the
  build the join clauses needed for a query dynamically and avoid adding
  unnecessary joins.

  ## Filtering by calculated values with subqueries

  You can join on a subquery with a named binding and add a join field as
  described above.

  Schema:

      @derive {
        Flop.Schema,
        filterable: [:pet_count],
        sortable: [:pet_count],
        join_fields: [pet_count: [{:pet_count, :count}]}

  Query:

      params = %{filters: [%{field: :pet_count, op: :>, value: 2}]}

      pet_count_query =
        Pet
        |> where([p], parent_as(:owner).id == p.owner_id)
        |> select([p], %{count: count(p)})

      q =
        (o in Owner)
        |> from(as: :owner)
        |> join(:inner_lateral, [owner: o], p in subquery(pet_count_query),
          as: :pet_count
        )
        |> Flop.validate_and_run(params, for: Owner)

  ## Custom fields

  If you need more control over the queries produced by the filters, you can
  define custom fields that reference a function which implements the filter
  logic. Custom field filters are referenced by
  `{mod :: module, function :: atom, opts :: keyword}`. The function will
  receive the Ecto query, the flop filter, and the option keyword list.

  If you need to pass in options at runtime (e.g. the timezone of the request,
  the user ID of the current user etc.), you can do so by passing in the
  `extra_opts` option to the flop functions. Currently, custom fields only
  support filtering and can not be used for sorting.

  Schema:

      @derive {
        Flop.Schema,
        filterable: [:inserted_at_date],
        custom_fields: [
          inserted_at_date: [
            filter: {CustomFilters, :date_filter, [source: :inserted_at]},
            ecto_type: :date
          ]
        ]
      }

  Filter module:

      defmodule CustomFilters do
        import Ecto.Query

        def date_filter(query, %Flop.Filter{value: value, op: op}, opts) do
          source = Keyword.fetch!(opts, :source)
          timezone = Keyword.fetch!(opts, :timezone)

          expr = dynamic([r], fragment("((? AT TIME ZONE 'utc') AT TIME ZONE ?)::date", field(r, ^source), ^timezone))

          case Ecto.Type.cast(:date, value) do
            {:ok, date} ->
              conditions =
                case op do
                  :>= -> dynamic([r], ^expr >= ^date)
                  :<= -> dynamic([r], ^expr <= ^date)
                end

              where(query, ^conditions)

            :error ->
              query
          end

        end
      end

  Query:

      Flop.validate_and_run(Flop.Pet, params, for: Flop.Pet, extra_opts: [timezone: timezone])

  """

  @fallback_to_any true

  @doc """
  Returns the field type in a schema.

  - `{:normal, atom}` - An ordinary field on the schema. The second tuple
    element is the field name.
  - `{:compound, [atom]}` - A combination of fields defined with the
    `compound_fields` option. The list of atoms refers to the list of fields
    that are included.
  - `{:join, map}` - A field from a named binding as defined with the
    `join_fields` option. The map has keys for the `:binding`, `:field` and
    `:path`.
  - `{:custom, keyword}` - A filter field that uses a custom filter function.

  ## Examples

      iex> field_type(%Flop.Pet{}, :age)
      {:normal, :age}
      iex> field_type(%Flop.Pet{}, :full_name)
      {:compound, [:family_name, :given_name]}
      iex> field_type(%Flop.Pet{}, :owner_name)
      {
        :join,
        %{
          binding: :owner,
          field: :name,
          path: [:owner, :name],
          ecto_type: :string
        }
      }
      iex> field_type(%Flop.Pet{}, :reverse_name)
      {
        :custom,
        %{
          filter: {Flop.Pet, :reverse_name_filter, []},
          ecto_type: :string
        }
      }
  """
  @doc since: "0.11.0"
  @spec field_type(any, atom) ::
          {:normal, atom}
          | {:compound, [atom]}
          | {:join, map}
          | {:alias, atom}
          | {:custom, map}
  def field_type(data, field)

  @doc """
  Returns the filterable fields of a schema.

      iex> Flop.Schema.filterable(%Flop.Pet{})
      [
        :age,
        :full_name,
        :name,
        :owner_age,
        :owner_name,
        :owner_tags,
        :pet_and_owner_name,
        :species,
        :tags,
        :custom,
        :reverse_name
      ]
  """
  @spec filterable(any) :: [atom]
  def filterable(data)

  @doc false
  @spec apply_order_by(any, Ecto.Query.t(), tuple | keyword) :: Ecto.Query.t()
  def apply_order_by(data, q, expr)

  @doc false
  @spec cursor_dynamic(any, keyword, map) :: any
  def cursor_dynamic(data, order, cursor_map)

  @doc """
  Gets the field value from a struct.

  Resolves join fields and compound fields according to the config.

      # join_fields: [owner_name: {:owner, :name}]
      iex> pet = %Flop.Pet{name: "George", owner: %Flop.Owner{name: "Carl"}}
      iex> Flop.Schema.get_field(pet, :name)
      "George"
      iex> Flop.Schema.get_field(pet, :owner_name)
      "Carl"

      # compound_fields: [full_name: [:family_name, :given_name]]
      iex> pet = %Flop.Pet{given_name: "George", family_name: "Gooney"}
      iex> Flop.Schema.get_field(pet, :full_name)
      "Gooney George"

  For join fields, this function relies on the binding name in the schema config
  matching the field name for the association in the struct.
  """
  @doc since: "0.13.0"
  @spec get_field(any, atom) :: any
  def get_field(data, field)

  @doc """
  Returns the allowed pagination types of a schema.

      iex> Flop.Schema.pagination_types(%Flop.Fruit{})
      [:first, :last, :offset]
  """
  @doc since: "0.9.0"
  @spec pagination_types(any) :: [Flop.pagination_type()] | nil
  def pagination_types(data)

  @doc """
  Returns the sortable fields of a schema.

      iex> Flop.Schema.sortable(%Flop.Pet{})
      [:name, :age, :owner_name, :owner_age]
  """
  @spec sortable(any) :: [atom]
  def sortable(data)

  @doc """
  Returns the default limit of a schema.

      iex> Flop.Schema.default_limit(%Flop.Fruit{})
      60
  """
  @doc since: "0.3.0"
  @spec default_limit(any) :: pos_integer | nil
  def default_limit(data)

  @doc """
  Returns the default order of a schema.

      iex> Flop.Schema.default_order(%Flop.Fruit{})
      %{order_by: [:name], order_directions: [:asc]}
  """
  @doc since: "0.7.0"
  @spec default_order(any) ::
          %{
            order_by: [atom] | nil,
            order_directions: [Flop.order_direction()] | nil
          }
          | nil
  def default_order(data)

  @doc """
  Returns the maximum limit of a schema.

      iex> Flop.Schema.max_limit(%Flop.Pet{})
      1000
  """
  @doc since: "0.2.0"
  @spec max_limit(any) :: pos_integer | nil
  def max_limit(data)
end

defimpl Flop.Schema, for: Any do
  @instructions """
  Flop.Schema protocol must always be explicitly implemented.

  To do this, you have to derive Flop.Schema in your Ecto schema module. You
  have to set both the filterable and the sortable option.

      @derive {
        Flop.Schema,
        filterable: [:name, :species],
        sortable: [:name, :age, :species]
      }

      schema "pets" do
        field :name, :string
        field :age, :integer
        field :species, :string
      end

  """
  # credo:disable-for-next-line
  defmacro __deriving__(module, struct, options) do
    validate_options!(options, struct)

    filterable_fields = Keyword.get(options, :filterable)
    sortable_fields = Keyword.get(options, :sortable)
    default_limit = Keyword.get(options, :default_limit)
    max_limit = Keyword.get(options, :max_limit)
    pagination_types = Keyword.get(options, :pagination_types)
    default_order = Keyword.get(options, :default_order)
    compound_fields = Keyword.get(options, :compound_fields, [])
    alias_fields = Keyword.get(options, :alias_fields, [])

    custom_fields =
      options
      |> Keyword.get(:custom_fields, [])
      |> Enum.map(&normalize_custom_opts/1)

    join_fields =
      options
      |> Keyword.get(:join_fields, [])
      |> Enum.map(&normalize_join_opts/1)

    field_type_func =
      build_field_type_func(
        compound_fields,
        join_fields,
        alias_fields,
        custom_fields
      )

    order_by_func =
      build_order_by_func(compound_fields, join_fields, alias_fields)

    get_field_func = build_get_field_func(compound_fields, join_fields)

    cursor_dynamic_func_compound =
      build_cursor_dynamic_func_compound(compound_fields)

    cursor_dynamic_func_join = build_cursor_dynamic_func_join(join_fields)
    cursor_dynamic_func_alias = build_cursor_dynamic_func_alias(alias_fields)
    cursor_dynamic_func_normal = build_cursor_dynamic_func_normal()

    quote do
      defimpl Flop.Schema, for: unquote(module) do
        import Ecto.Query

        require Logger

        def default_limit(_) do
          unquote(default_limit)
        end

        def default_order(_) do
          unquote(Macro.escape(default_order))
        end

        unquote(field_type_func)
        unquote(order_by_func)
        unquote(get_field_func)

        def filterable(_) do
          unquote(filterable_fields)
        end

        def max_limit(_) do
          unquote(max_limit)
        end

        def pagination_types(_) do
          unquote(pagination_types)
        end

        def sortable(_) do
          unquote(sortable_fields)
        end

        def cursor_dynamic(_, [], _), do: true

        unquote(cursor_dynamic_func_compound)
        unquote(cursor_dynamic_func_join)
        unquote(cursor_dynamic_func_alias)
        unquote(cursor_dynamic_func_normal)
      end
    end
  end

  defp validate_options!(opts, struct) do
    if is_nil(opts[:filterable]) || is_nil(opts[:sortable]),
      do: raise(ArgumentError, @instructions)

    compound_fields = get_compound_fields(opts)
    join_fields = get_join_fields(opts)
    schema_fields = get_schema_fields(struct)
    alias_fields = Keyword.get(opts, :alias_fields, [])
    custom_fields = get_custom_fields(opts)

    all_fields =
      compound_fields ++
        join_fields ++ schema_fields ++ alias_fields ++ custom_fields

    validate_no_duplicate_fields!(
      compound_fields ++ join_fields ++ alias_fields ++ custom_fields
    )

    validate_limit!(opts[:default_limit], "default")
    validate_limit!(opts[:max_limit], "max")
    validate_pagination_types!(opts[:pagination_types])
    check_legacy_default_order(opts)
    validate_no_unknown_options!(opts)
    validate_no_unknown_field!(opts[:filterable], all_fields, "filterable")
    validate_no_unknown_field!(opts[:sortable], all_fields, "sortable")
    validate_default_order!(opts[:default_order], opts[:sortable])
    validate_compound_fields!(opts[:compound_fields], all_fields)
    validate_alias_fields!(alias_fields, opts[:filterable])
    validate_custom_fields!(opts[:custom_fields], opts[:sortable])
  end

  defp get_compound_fields(opts) do
    opts |> Keyword.get(:compound_fields, []) |> Keyword.keys()
  end

  defp get_join_fields(opts) do
    opts |> Keyword.get(:join_fields, []) |> Keyword.keys()
  end

  defp get_custom_fields(opts) do
    opts |> Keyword.get(:custom_fields, []) |> Keyword.keys()
  end

  defp get_schema_fields(struct) do
    # reflection functions are not available during compilation
    struct
    |> Map.from_struct()
    |> Enum.reject(fn
      {_, %Ecto.Association.NotLoaded{}} -> true
      {:__meta__, _} -> true
      _ -> false
    end)
    |> Enum.map(fn {field, _} -> field end)
  end

  defp validate_limit!(nil, _), do: :ok
  defp validate_limit!(i, _) when is_integer(i) and i > 0, do: :ok

  defp validate_limit!(i, type) do
    raise ArgumentError, """
    invalid #{type} limit

    expected non-negative integer, got: #{inspect(i)}
    """
  end

  defp validate_pagination_types!(nil), do: :ok

  defp validate_pagination_types!(types) when is_list(types) do
    valid_types = [:offset, :page, :first, :last]
    unknown = Enum.uniq(types) -- valid_types

    if unknown != [] do
      raise ArgumentError,
            """
            invalid pagination type

            expected one of #{inspect(valid_types)}, got: #{inspect(unknown)}
            """
    end
  end

  defp validate_pagination_types!(types) do
    raise ArgumentError, """
    invalid pagination type

    expected list of atoms, got: #{inspect(types)}
    """
  end

  defp validate_no_unknown_options!(opts) do
    known_keys = [
      :alias_fields,
      :compound_fields,
      :custom_fields,
      :default_limit,
      :default_order,
      :filterable,
      :join_fields,
      :max_limit,
      :pagination_types,
      :sortable
    ]

    unknown_keys = Keyword.keys(opts) -- known_keys

    if unknown_keys != [] do
      raise ArgumentError, "unknown option(s): #{inspect(unknown_keys)}"
    end
  end

  defp validate_no_unknown_field!(fields, known_fields, type) do
    unknown_fields = fields -- known_fields

    if unknown_fields != [] do
      raise ArgumentError,
            "unknown #{type} field(s): #{inspect(unknown_fields)}"
    end
  end

  defp validate_default_order!(nil, _), do: :ok

  defp validate_default_order!(%{} = map, sortable_fields) do
    if Map.keys(map) -- [:order_by, :order_directions] != [] do
      raise ArgumentError, default_order_error(map)
    end

    order_by = Map.get(map, :order_by, [])
    order_directions = Map.get(map, :order_directions, [])

    if !is_list(order_by) || !is_list(order_directions) do
      raise ArgumentError, default_order_error(map)
    end

    unsortable_fields = Enum.uniq(order_by) -- sortable_fields

    if unsortable_fields != [] do
      raise ArgumentError, """
      invalid default order

      Default order fields must be sortable, but these fields are not:

          #{inspect(unsortable_fields)}
      """
    end

    valid_directions = [
      :asc,
      :asc_nulls_first,
      :asc_nulls_last,
      :desc,
      :desc_nulls_first,
      :desc_nulls_last
    ]

    invalid_directions = Enum.uniq(order_directions) -- valid_directions

    if invalid_directions != [] do
      raise ArgumentError, """
      invalid default order

      Invalid order direction(s):

          #{inspect(invalid_directions)}
      """
    end
  end

  defp validate_default_order!(value, _) do
    raise ArgumentError, default_order_error(value)
  end

  defp default_order_error(value) do
    """
    invalid default order

    expected a map like this:

        %{order_by: [:some_field], order_directions: [:asc]}

    got:

        #{inspect(value)}
    """
  end

  defp validate_compound_fields!(nil, _), do: :ok

  defp validate_compound_fields!(compound_fields, known_fields)
       when is_list(compound_fields) do
    Enum.each(compound_fields, fn {field, fields} ->
      unknown_fields = fields -- known_fields

      if unknown_fields != [] do
        raise ArgumentError, """
        compound field references unknown field(s)

        Compound fields must reference existing fields, but #{inspect(field)}
        references:

            #{inspect(unknown_fields)}
        """
      end
    end)
  end

  defp validate_alias_fields!(alias_fields, filterable)
       when is_list(alias_fields) do
    illegal_fields = Enum.filter(alias_fields, &(&1 in filterable))

    if illegal_fields != [] do
      raise ArgumentError, """
      cannot filter by alias fields

      Alias fields are not allowed to be filterable. These alias fields were
      configured as filterable:

          #{inspect(illegal_fields)}

      Use custom fields if you want to implement custom filtering.
      """
    end
  end

  defp validate_custom_fields!(nil, _), do: :ok

  defp validate_custom_fields!(custom_fields, sortable)
       when is_list(custom_fields) do
    illegal_fields =
      Enum.filter(custom_fields, fn {field, _} -> field in sortable end)

    if illegal_fields != [] do
      raise ArgumentError, """
      cannot sort by custom fields

      Custom fields are not allowed to be sortable. These custom fields were
      configured as sortable:

          #{inspect(illegal_fields)}

      Use alias fields if you want to implement custom sorting.
      """
    end
  end

  defp validate_no_duplicate_fields!(fields) do
    duplicates = duplicate_fields(fields)

    if duplicates != [] do
      raise ArgumentError, """
      duplicate fields

      Alias field, compound field and join field names must be unique. These
      field names were used multiple times:

          #{inspect(duplicates)}
      """
    end
  end

  defp duplicate_fields(fields) do
    fields
    |> Enum.frequencies()
    |> Enum.filter(fn {_, count} -> count > 1 end)
    |> Enum.map(fn {field, _} -> field end)
  end

  defp check_legacy_default_order(opts) do
    if order_by = Keyword.get(opts, :default_order_by) do
      directions = Keyword.get(opts, :default_order_directions)

      raise """
      The default order needs to be updated.

      Please change your schema config to:

          @derive {
            Flop.Schema,
            # ...
            default_order: %{
              order_by: #{inspect(order_by)},
              order_directions: #{inspect(directions)}
            }
          }
      """
    end
  end

  def normalize_custom_opts({name, opts}) when is_list(opts) do
    opts = %{
      filter: Keyword.fetch!(opts, :filter),
      ecto_type: Keyword.get(opts, :ecto_type)
    }

    {name, opts}
  end

  def normalize_join_opts({name, opts}) do
    opts =
      case opts do
        {binding, field} ->
          %{
            binding: binding,
            field: field,
            path: [binding, field],
            ecto_type: nil
          }

        opts when is_list(opts) ->
          binding = Keyword.fetch!(opts, :binding)
          field = Keyword.fetch!(opts, :field)

          %{
            binding: binding,
            field: field,
            path: opts[:path] || [binding, field],
            ecto_type: Keyword.get(opts, :ecto_type)
          }
      end

    {name, opts}
  end

  def build_field_type_func(
        compound_fields,
        join_fields,
        alias_fields,
        custom_fields
      ) do
    compound_field_funcs = field_type_funcs(:compound, compound_fields)
    join_field_funcs = field_type_funcs(:join, join_fields)
    alias_field_funcs = field_type_funcs(:alias, alias_fields)
    custom_field_funcs = field_type_funcs(:custom, custom_fields)

    default_funcs =
      quote do
        def field_type(_, name) do
          {:normal, name}
        end
      end

    quote do
      unquote(compound_field_funcs)
      unquote(join_field_funcs)
      unquote(alias_field_funcs)
      unquote(custom_field_funcs)
      unquote(default_funcs)
    end
  end

  defp field_type_funcs(type, fields)
       when type in [:compound, :join, :custom] do
    for {name, value} <- fields do
      quote do
        def field_type(_, unquote(name)) do
          {unquote(type), unquote(Macro.escape(value))}
        end
      end
    end
  end

  defp field_type_funcs(:alias, fields) do
    for name <- fields do
      quote do
        def field_type(_, unquote(name)) do
          {:alias, unquote(name)}
        end
      end
    end
  end

  def build_cursor_dynamic_func_compound(compound_fields) do
    for {compound_field, _fields} <- compound_fields do
      quote do
        def cursor_dynamic(_, [{_, unquote(compound_field)}], _) do
          Logger.warn(
            "Flop: Cursor pagination is not supported for compound fields. Ignored."
          )

          true
        end

        def cursor_dynamic(
              struct,
              [{_, unquote(compound_field)} | tail],
              cursor
            ) do
          Logger.warn(
            "Flop: Cursor pagination is not supported for compound fields. Ignored."
          )

          cursor_dynamic(struct, tail, cursor)
        end
      end
    end
  end

  def build_cursor_dynamic_func_alias(alias_fields) do
    for name <- alias_fields do
      quote do
        def cursor_dynamic(_, [{_, unquote(name)} | _], _) do
          raise "alias fields are not supported in cursor pagination"
        end
      end
    end
  end

  # credo:disable-for-next-line
  def build_cursor_dynamic_func_join(join_fields) do
    for {join_field, %{binding: binding, field: field}} <- join_fields do
      bindings = Code.string_to_quoted!("[#{binding}: r]")

      quote do
        def cursor_dynamic(_, [{direction, unquote(join_field)}], cursor)
            when direction in [:asc, :asc_nulls_first, :asc_nulls_last] do
          field_cursor = cursor[unquote(join_field)]

          if is_nil(field_cursor) do
            true
          else
            dynamic(
              unquote(bindings),
              field(r, unquote(field)) > ^field_cursor
            )
          end
        end

        def cursor_dynamic(_, [{direction, unquote(join_field)}], cursor)
            when direction in [:desc, :desc_nulls_first, :desc_nulls_last] do
          field_cursor = cursor[unquote(join_field)]

          if is_nil(field_cursor) do
            true
          else
            dynamic(
              unquote(bindings),
              field(r, unquote(field)) < ^field_cursor
            )
          end
        end

        def cursor_dynamic(
              struct,
              [{direction, unquote(join_field)} | [{_, _} | _] = tail],
              cursor
            ) do
          field_cursor = cursor[unquote(join_field)]

          if is_nil(field_cursor) do
            cursor_dynamic(struct, tail, cursor)
          else
            case direction do
              dir when dir in [:asc, :asc_nulls_first, :asc_nulls_last] ->
                dynamic(
                  unquote(bindings),
                  field(r, unquote(field)) >= ^field_cursor and
                    (field(r, unquote(field)) > ^field_cursor or
                       ^cursor_dynamic(struct, tail, cursor))
                )

              dir when dir in [:desc, :desc_nulls_first, :desc_nulls_last] ->
                dynamic(
                  unquote(bindings),
                  field(r, unquote(field)) <= ^field_cursor and
                    (field(r, unquote(field)) < ^field_cursor or
                       ^cursor_dynamic(struct, tail, cursor))
                )
            end
          end
        end
      end
    end
  end

  # credo:disable-for-next-line
  def build_cursor_dynamic_func_normal do
    quote do
      def cursor_dynamic(_, [{direction, field}], cursor) do
        field_cursor = cursor[field]

        if is_nil(field_cursor) do
          true
        else
          case direction do
            dir when dir in [:asc, :asc_nulls_first, :asc_nulls_last] ->
              dynamic([r], field(r, ^field) > ^cursor[field])

            dir when dir in [:desc, :desc_nulls_first, :desc_nulls_last] ->
              dynamic([r], field(r, ^field) < ^cursor[field])
          end
        end
      end

      def cursor_dynamic(
            struct,
            [{direction, field} | [{_, _} | _] = tail],
            cursor
          ) do
        field_cursor = cursor[field]

        if is_nil(field_cursor) do
          Flop.Schema.cursor_dynamic(struct, tail, cursor)
        else
          case direction do
            dir when dir in [:asc, :asc_nulls_first, :asc_nulls_last] ->
              dynamic(
                [r],
                field(r, ^field) >= ^field_cursor and
                  (field(r, ^field) > ^field_cursor or
                     ^Flop.Schema.cursor_dynamic(struct, tail, cursor))
              )

            dir when dir in [:desc, :desc_nulls_first, :desc_nulls_last] ->
              dynamic(
                [r],
                field(r, ^field) <= ^field_cursor and
                  (field(r, ^field) < ^field_cursor or
                     ^Flop.Schema.cursor_dynamic(struct, tail, cursor))
              )
          end
        end
      end
    end
  end

  def build_order_by_func(compound_fields, join_fields, alias_fields) do
    compound_field_funcs =
      for {name, fields} <- compound_fields do
        quote do
          def apply_order_by(struct, q, {direction, unquote(name)}) do
            Enum.reduce(unquote(fields), q, fn field, acc_q ->
              Flop.Schema.apply_order_by(struct, acc_q, {direction, field})
            end)
          end
        end
      end

    join_field_funcs =
      for {join_field, %{binding: binding, field: field}} <- join_fields do
        bindings = Code.string_to_quoted!("[#{binding}: r]")

        quote do
          def apply_order_by(_struct, q, {direction, unquote(join_field)}) do
            order_by(
              q,
              unquote(bindings),
              [{^direction, field(r, unquote(field))}]
            )
          end
        end
      end

    alias_field_func =
      for name <- alias_fields do
        quote do
          def apply_order_by(_struct, q, {direction, unquote(name)}) do
            order_by(q, [{^direction, selected_as(unquote(name))}])
          end
        end
      end

    normal_field_func =
      quote do
        def apply_order_by(_struct, q, direction) do
          order_by(q, ^direction)
        end
      end

    quote do
      unquote(compound_field_funcs)
      unquote(join_field_funcs)
      unquote(alias_field_func)
      unquote(normal_field_func)
    end
  end

  def build_get_field_func(compound_fields, join_fields) do
    compound_field_funcs =
      for {name, fields} <- compound_fields do
        quote do
          def get_field(struct, unquote(name)) do
            Enum.map_join(
              unquote(fields),
              " ",
              &Flop.Schema.get_field(struct, &1)
            )
          end
        end
      end

    join_field_funcs =
      for {name, %{path: path}} <- join_fields do
        quote do
          def get_field(struct, unquote(name)) do
            Enum.reduce(unquote(path), struct, fn field, acc ->
              case acc do
                %{} -> Map.get(acc, field)
                _ -> nil
              end
            end)

            # assoc = Map.get(struct, unquote(assoc_field)) || %{}
            # Map.get(assoc, unquote(field))
          end
        end
      end

    fallback_func =
      quote do
        def get_field(struct, field), do: Map.get(struct, field)
      end

    quote do
      unquote(compound_field_funcs)
      unquote(join_field_funcs)
      unquote(fallback_func)
    end
  end

  function_names = [
    :default_limit,
    :default_order,
    :filterable,
    :max_limit,
    :pagination_types,
    :sortable
  ]

  for function_name <- function_names do
    def unquote(function_name)(struct) do
      raise Protocol.UndefinedError,
        protocol: @protocol,
        value: struct,
        description: @instructions
    end
  end

  def field_type(struct, _) do
    raise Protocol.UndefinedError,
      protocol: @protocol,
      value: struct,
      description: @instructions
  end

  def apply_order_by(struct, _, _) do
    raise Protocol.UndefinedError,
      protocol: @protocol,
      value: struct,
      description: @instructions
  end

  def cursor_dynamic(struct, _, _) do
    raise Protocol.UndefinedError,
      protocol: @protocol,
      value: struct,
      description: @instructions
  end

  # add default implementation for maps, so that cursor value functions can use
  # it without checking protocol implementation
  def get_field(%{} = map, field), do: Map.get(map, field)

  def get_field(thing, _) do
    raise Protocol.UndefinedError,
      protocol: @protocol,
      value: thing,
      description: @instructions
  end
end
