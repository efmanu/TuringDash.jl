module TuringDash


include("render_funcs.jl")
include("utils.jl")
using Dash, DashBootstrapComponents
using DashHtmlComponents, DashCoreComponents
using PlotlyJS
using Turing
using Random
using CSV, DataFrames

#Initialize channel to get data during optimization
chn = Base.Channel{Vector{Float64}}(Inf)
x_graph = []
y_graph = []
y_graph1 = []
itr = 0
eval_f = nothing
range_value = []

function make_app()
    global chn, x_graph, y_graph, itr, eval_f
    global range_value

    chn = Base.Channel{Vector{Float64}}(Inf)
    x_graph = []
	y_graph = []
    y_graph1 = []
    itr = 0
    
    external_stylesheets = "https://cdnjs.cloudflare.com/ajax/libs/font-awesome/4.7.0/css/font-awesome.min.css"
    app = dash(external_stylesheets=[dbc_themes.BOOTSTRAP,external_stylesheets], 
	    suppress_callback_exceptions=true)
    
    app.layout = html_div([
        render_all()
    ])
    callback!(app,
        Output("dtu-params-plot-loc", "children"),      
        Input("dtu-btn-turing", "n_clicks"),
        Input("dtu-upload-datan", "contents"),
        State("dtu-def-data-drop", "value"),
        State("dtu-user-funcs", "value"),
        State("dtu-user-func-init", "value"),
        State("dtu-upload-datan", "filename")        
    ) do n_clicks, contents, drop_val, user_funcs, funcs_init, filename
        ctx = callback_context()
        if isempty(ctx.triggered)
            throw(PreventUpdate())
        end
        if !(ctx.triggered[1].prop_id == "dtu-btn-turing.n_clicks")
            throw(PreventUpdate())
        end
        if (contents isa Nothing) && (drop_val == "0")
            throw(PreventUpdate())
        end
        if (user_funcs == "") || (funcs_init == "")
            throw(PreventUpdate())
        end
        global chn
        global chn, x_graph, y_graph, y_graph1, itr
        x_graph = []
        y_graph = []
        y_graph1 = []
        itr = 0
        if contents isa Nothing
            df = load_default(drop_val)
        else
            df = parse_contents(contents, filename)
        end        
        for colname in Symbol.(names(df))
            @eval $colname = df.$colname
        end         
        
        #evealuate model
        eval(Meta.parse(user_funcs))

        #evaluate eval_definition
        model = eval(Meta.parse(funcs_init))

        alg = MH()
        rng = Random.GLOBAL_RNG

        nperiteration = 5
        nsamples = 1000
        @async begin
            r = sample(rng, model, spl, nperiteration; chain_type=MCMCChains.Chains, save_state=true)
            put!(chn, Array(r)[end,1:2])
            for i in (nperiteration + 1):nperiteration:nsamples
                r = Turing.Inference.resume(r, nperiteration, save_state=true)
                put!(chn, Array(r)[end,1:2])
            end
        end
        @show nsamples
        return "render_liveupdates()"
    end

    callback!(app,
        Output("dtu-params-state1", "figure"),
        Output("dtu-params-state2", "figure"),
        Output("interval-component", "disabled"),
        Input("interval-component", "n_intervals"),
        State("dtu-params-state1", "figure"),
        State("dtu-params-state2", "figure"),
        prevent_initial_call=true) do n, state_fig1, state_fig2
        st = false
        global x_graph, y_graph, y_graph1, chn, itr
        if isready(chn)
            val = take!(chn)
            itr += 1
            append!(x_graph, itr)
            append!(y_graph, val[1])
			append!(y_graph1, val[2])
        else
            st = true
        end
        return Dict(
            "data" => [
                    Dict(
                        "x" => x_graph,
                        "y" => y_graph,
                        "mode" => "line",
                    )
                ]
            ),
            Dict(
                "data" => [
                    Dict(
                        "x" => x_graph,
                        "y" => y_graph1,
                        "mode" => "line",
                    )
                ]
            ), st
    end
    return app
end

end # module
