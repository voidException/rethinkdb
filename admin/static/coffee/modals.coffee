# Copyright 2010-2012 RethinkDB, all rights reserved.

module 'Modals', ->
    class @AddDatabaseModal extends UIComponents.AbstractModal
        template: Handlebars.templates['add_database-modal-template']
        templates:
            error: Handlebars.templates['error_input-template']

        class: 'add-database'

        initialize: (databases) =>
            super
            @databases = databases


        render: =>
            super
                modal_title: "Add database"
                btn_primary_text: "Add"
            @$('.focus_new_name').focus()

        on_submit: =>
            super
            @formdata = form_data_as_object($('form', @$modal))

            error = null

            # Validate input
            if @formdata.name is ''
                # Empty name is not valid
                error = true
                @$('.alert_modal').html @templates.error
                    database_is_empty: true
            else if /^[a-zA-Z0-9_]+$/.test(@formdata.name) is false
                # Only alphanumeric char + underscore are allowed
                error = true
                @$('.alert_modal').html @templates.error
                    special_char_detected: true
                    type: 'database'
            else
                # Check if it's a duplicate
                for database in @databases.models
                    if database.get('db') is @formdata.name
                        error = true
                        @$('.alert_modal').html @templates.error
                            database_exists: true
                        break

            if error is null
                driver.run_once r.db(system_db).table("db_config").insert({name: @formdata.name}), (err, result) =>
                    if (err)
                        @on_error(err)
                    else
                        if result.inserted is 1
                            @databases.add new Database
                                id: result.generated_keys[0]
                                name: @formdata.name
                                tables: []
                            @on_success()
                        else
                            @on_error(new Error(result.first_error or "Unknown error"))
            else
                $('.alert_modal_content').slideDown 'fast'
                @reset_buttons()

        on_success: (response) =>
            super()
            window.app.current_view.render_message "The database #{@formdata.name} was successfully created."

    class @RemoveDatabaseModal extends UIComponents.AbstractModal
        template: Handlebars.templates['remove_database-modal-template']
        class: 'remove_database-dialog'

        render: (database_to_delete) ->
            @database_to_delete = database_to_delete

            # Call render of AbstractModal with the data for the template
            super
                modal_title: 'Delete database'
                btn_primary_text: 'Delete'

            @$('.verification_name').focus()


        on_submit: =>
            if @$('.verification_name').val() isnt @database_to_delete.get('name')
                if @$('.mismatch_container').css('display') is 'none'
                    @$('.mismatch_container').slideDown('fast')
                else
                    @$('.mismatch_container').hide()
                    @$('.mismatch_container').fadeIn()
                @reset_buttons()
                return true

            super

            driver.run_once r.dbDrop(@database_to_delete.get('name')), (err, result) =>
                if (err)
                    @on_error(err)
                else
                    if result?.dropped is 1
                        @on_success()
                    else
                        @on_error(new Error("The return result was not `{dropped: 1}`"))

        on_success: (response) =>
            super()
            if Backbone.history.fragment is 'tables'
                @database_to_delete.destroy()
            else
                # If the user was on a database view, we have to redirect him
                # If he was on #tables, we are just refreshing
                main_view.router.navigate '#tables', {trigger: true}

            window.app.current_view.render_message "The database #{@database_to_delete.get('name')} was successfully deleted."

    class @AddTableModal extends UIComponents.AbstractModal
        template: Handlebars.templates['add_table-modal-template']
        templates:
            error: Handlebars.templates['error_input-template']
        class: 'add-table'

        initialize: (data) =>
            super
            @databases = data.databases
            @container = data.container

            @listenTo @databases, 'all', @check_if_can_create_table

            @can_create_table_status = true
            @delegateEvents()


        show_advanced_settings: (event) =>
            event.preventDefault()
            @$('.show_advanced_settings-link_container').fadeOut 'fast', =>
                @$('.hide_advanced_settings-link_container').fadeIn 'fast'
            @$('.advanced_settings').slideDown 'fast'

        hide_advanced_settings: (event) =>
            event.preventDefault()
            @$('.hide_advanced_settings-link_container').fadeOut 'fast', =>
                $('.show_advanced_settings-link_container').fadeIn 'fast'
            @$('.advanced_settings').slideUp 'fast'

        # Check if we have a database (if not, we cannot create a table)
        check_if_can_create_table: =>
            if @databases.length is 0
                if @can_create_table_status
                    @$('.btn-primary').prop 'disabled', true
                    @$('.alert_modal').html @templates.error
                        create_db_first: true
                    $('.alert_modal_content').slideDown 'fast'
            else
                if @can_create_table_status is false
                    @$('.alert_modal').empty()
                    @$('.btn-primary').prop 'disabled', false


        render: =>
            ordered_databases = @databases.map (d) ->
                name: d.get('name')
            ordered_databases = _.sortBy ordered_databases, (d) -> d.db

            super
                modal_title: 'Add table'
                btn_primary_text: 'Add'
                databases: ordered_databases

            @check_if_can_create_table()
            @$('.show_advanced_settings-link').click @show_advanced_settings
            @$('.hide_advanced_settings-link').click @hide_advanced_settings

            @$('#focus_table_name').focus()

        on_submit: =>
            super

            @formdata = form_data_as_object($('form', @$modal))
            # Check if data is safe
            template_error = {}
            input_error = false

            if @formdata.name is '' # Need a name
                input_error = true
                template_error.table_name_empty = true
            else if /^[a-zA-Z0-9_]+$/.test(@formdata.name) is false
                input_error = true
                template_error.special_char_detected = true
                template_error.type = 'table'
            else if not @formdata.database? or @formdata.database is ''
                input_error = true
                template_error.no_database = true
            else # And a name that doesn't exist
                database_used = null
                for database in @databases.models
                    if database.get('name') is @formdata.database
                        database_used = database
                        break

                for table in database_used.get('tables')
                    if table.name is @formdata.name
                        input_error = true
                        template_error.table_exists = true
                        break


            if input_error is true
                $('.alert_modal').html @templates.error template_error
                $('.alert_modal_content').slideDown 'fast'
                @reset_buttons()
            else
                # TODO Add durability in the query when the API will be available
                if @formdata.write_disk is 'yes'
                    durability = 'soft'
                else
                    durability = 'hard'

                if @formdata.primary_key isnt ''
                    primary_key = @formdata.primary_key
                else
                    primary_key = 'id'


                query = r.db(system_db).table("server_status").filter({status: "available"}).coerceTo("ARRAY").do (servers) =>
                    r.branch(
                        servers.isEmpty(),
                        r.error("No server is available"),
                        servers.sample(1).nth(0)("name").do( (server) =>
                            r.db(system_db).table("table_config").insert
                                db: @formdata.database
                                name: @formdata.name
                                primary_key: primary_key
                                shards: [
                                    #TODO: replace with primary once api changes
                                    director: server
                                    replicas: [server]
                                ]
                            ,
                                returnChanges: true
                        )
                    )

                driver.run_once query, (err, result) =>
                    if (err)
                        @on_error(err)
                    else
                        if result?.errors is 0
                            db = @databases.filter( (database) => database.get('name') is @formdata.database)[0]
                            db.set
                                tables: db.get('tables').concat _.extend result.changes[0].new_val,
                                    shards: 1
                                    replicas: 1
                                    ready_completely: "N/A"
                                    id: result.generated_keys[0]

                            # We suppose that after one second, the data will be available
                            # So the yellow light will be replaced with a green one
                            setTimeout @container.fetch_data_once, 1000

                            @on_success()
                        else
                            @on_error(new Error("The returned result was not `{created: 1}`"))

        on_success: (response) =>
            super
            window.app.current_view.render_message "The table #{@formdata.database}.#{@formdata.name} was successfully created."

        remove: =>
            @stopListening()
            super()

    class @RemoveTableModal extends UIComponents.AbstractModal
        template: Handlebars.templates['remove_table-modal-template']
        class: 'remove-namespace-dialog'

        render: (tables_to_delete) =>
            @tables_to_delete = tables_to_delete

            super
                modal_title: 'Delete tables'
                btn_primary_text: 'Delete'
                tables: tables_to_delete
                single_delete: tables_to_delete.length is 1

            @$('.btn-primary').focus()

        on_submit: =>
            super

            query = r.db(system_db).table('table_config').filter( (table) =>
                r.expr(@tables_to_delete).contains(
                    database: table("db")
                    table: table("name")
                )
            ).delete({returnChanges: true})

            driver.run_once query, (err, result) =>
                if (err)
                    @on_error(err)
                else
                    if @collection? and result?.changes?
                        for change in result.changes
                            keep_going = true
                            for database in @collection.models
                                if keep_going is false
                                    break

                                if database.get('name') is change.old_val.db
                                    for table, position in database.get('tables')
                                        if table.name is change.old_val.name
                                            database.set
                                                tables: database.get('tables').slice(0, position).concat(database.get('tables').slice(position+1))
                                            keep_going = false
                                            break

                    if result?.deleted is @tables_to_delete.length
                        @on_success()
                    else
                        @on_error(new Error("The value returned for `deleted` did not match the number of tables."))


        on_success: (response) =>
            super

            # Build feedback message
            message = "The tables "
            for table, index in @tables_to_delete
                message += "#{table.database}.#{table.table}"
                if index < @tables_to_delete.length-1
                    message += ", "
            if @tables_to_delete.length is 1
                message += " was"
            else
                message += " were"
            message += " successfully deleted."

            if Backbone.history.fragment isnt 'tables'
                main_view.router.navigate '#tables', {trigger: true}
            window.app.current_view.render_message message
            @remove()

    class @RemoveServerModal extends UIComponents.AbstractModal
        template: Handlebars.templates['declare_server_dead-modal-template']
        alert_tmpl: Handlebars.templates['resolve_issues-resolved-template']
        template_issue_error: Handlebars.templates['fail_solve_issue-template']

        class: 'declare-server-dead'

        initialize: (data) ->
            @model = data.model
            super @template

        render:  ->
            super
                server_name: @model.get("name")
                modal_title: "Permanently remove the server"
                btn_primary_text: 'Remove ' + @model.get('name')
            @

        on_submit: ->
            super

            if @$('.verification').val().toLowerCase() is 'remove'
                query = r.db('rethinkdb').table('table_config')
                    .get(@model.get('id')).delete()
                driver.run_once query, (err, result) =>
                        if err?
                            @on_success_with_error()
                        else
                            @on_success()
            else
                @$('.error_verification').slideDown 'fast'
                @reset_buttons()

        on_success_with_error: =>
            @$('.error_answer').html @template_issue_error

            if @$('.error_answer').css('display') is 'none'
                @$('.error_answer').slideDown('fast')
            else
                @$('.error_answer').css('display', 'none')
                @$('.error_answer').fadeIn()
            @reset_buttons()


        on_success: (response) ->
            if (response)
                @on_success_with_error()
                return

            # notify the user that we succeeded
            $('#issue-alerts').append @alert_tmpl
                server_dead:
                    server_name: @model.get("name")
            @remove()

            @model.get('parent').set('fixed', true)
            @

    # Modals.ReconfigureModal
    class @ReconfigureModal extends UIComponents.AbstractModal
        template: Handlebars.templates['reconfigure-modal']

        class: 'reconfigure-modal'

        events:
            'keyup .replicas.inline-edit': 'change_replicas'
            'keyup .shards.inline-edit': 'change_shards'

        initialize: (obj) =>
            @fetch_dryrun()
            @listenTo @model, 'change:num_replicas_per_shard', @fetch_dryrun
            @listenTo @model, 'change:num_shards', @fetch_dryrun
            super(obj)

        render: =>
            console.log 'rendering modal'
            super $.extend(@model.toJSON(),
                modal_title: "Reconfigure #{@model.get('db')}.#{@model.get('name')}"
                btn_primary_text: 'Apply'
            )

            @diff_view = new TableView.ReconfigureDiffView
                model: @model
                el: @$('.reconfigure-diff')[0]
            @
        
        remove: =>
            if diff_view?
                diff_view.remove()
            super()
            
        change_replicas: =>
            num = parseInt @$('.replicas.inline-edit').val()
            if not isNaN num
                @model.set 'num_replicas_per_shard', num

        change_shards: =>
            num = parseInt @$('.shards.inline-edit').val()
            if not isNaN num
                @model.set 'num_shards', num

        fetch_dryrun: =>
            
            if not @model.get('num_shards')? or not @model.get('num_replicas_per_shard')?
                return
            id = (x) -> x
            query = r.db(@model.get('db'))
                .table(@model.get('name'))
                .reconfigure
                    shards: @model.get('num_shards')
                    replicas: @model.get('num_replicas_per_shard')
                    dryRun: true
                .do((diff) ->
                    r.object(r.args(diff.keys().map((key) ->
                        [key, diff(key)('config')('shards')]
                    ).concatMap(id)))
                ).do((doc) ->
                    doc.merge
                        # this creates a servername -> id map we can
                        # use later to create the links
                        lookups: r.object(r.args(
                            doc('new_val')('replicas').concatMap(id)
                                .setUnion(doc('old_val')('replicas').concatMap(id))
                                .concatMap (server) -> [
                                    server,
                                    r.db(system_db).table('server_status')
                                        .filter(name: server)(0)('id')
                                ]
                        ))
                )
                
            driver.run_once query, (error, result) =>
                if error?
                    @model.set
                        error: error.message
                else
                    @model.set
                        shards: @fixup_shards result.old_val,
                            result.new_val
                            result.lookups
                        error: null

        # Sorts shards in order of current primary first, old primary (if
        # any), then secondaries in lexicographic order
        shard_sort: (a, b) ->
            if a.role == 'primary'
                -1
            else if 'primary' in [b.role, b.old_role]
                +1
            else if a.role == b.role
                if a.name == b.name
                    0
                else if a.name < b.name
                    -1
                else
                    +1

        # determines role of a replica
        role: (isPrimary) ->
            if isPrimary then 'primary' else 'secondary'

        fixup_shards: (old_shards, new_shards, lookups) =>
            shard_diffs = []
            docs_per_shard = Math.round(
                @model.get('total_keys') / new_shards.length)

            # first handle shards that are in old (and possibly in new)
            for old_shard, i in old_shards
                if i >= new_shards.length
                    new_shard = {director: null, replicas: []}
                    shard_deleted = true
                    num_docs = 0
                else
                    new_shard = new_shards[i]
                    shard_deleted = false
                    num_docs = docs_per_shard

                shard_diff =
                    replicas: []
                    change: if shard_deleted then 'deleted' else null
                    num_docs: num_docs

                # handle any deleted and remaining replicas for this shard
                for replica in old_shard.replicas
                    replica_deleted = replica not in new_shard.replicas
                    if replica_deleted
                        new_role = null
                    else
                        new_role = @role(replica == new_shard.director)
                    old_role = @role(replica == old_shard.director)

                    shard_diff.replicas.push
                        name: replica
                        id: lookups[replica]
                        change: if replica_deleted then 'deleted' else null
                        role: new_role
                        old_role: old_role
                        role_change: not replica_deleted and new_role != old_role
                # handle any new replicas for this shard
                for replica in new_shard.replicas
                    if replica in old_shard.replicas
                        continue
                    shard_diff.replicas.push
                        name: replica
                        id: lookups[replica]
                        change: 'added'
                        role: @role(replica == new_shard.director)
                        old_role: null
                        role_change: false

                shard_diff.replicas.sort @shard_sort
                shard_diffs.push(shard_diff)
            # now handle any new shards beyond what old_shards has
            for new_shard in new_shards.slice(old_shards.length)
                shard_diff =
                    replicas: []
                    change: 'added'
                    num_docs: docs_per_shard
                for replica in new_shard.replicas
                    shard_diff.replicas.push
                        name: replica
                        id: lookups[replica]
                        change: 'added'
                        role: @role(replica == new_shard.director)
                        old_role: null
                        role_change: false
                shard_diff.replicas.sort @shard_sort
                shard_diffs.push(shard_diff)
            shard_diffs
