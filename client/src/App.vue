<template>
  <v-app>
    <v-content>
      <v-container>
        <!-- query input -->
        <v-row justify="center">
          <v-col cols="10">
            <v-text-field
              ref="query"
              class="display-3 text--primary"
              single-line
              v-model.trim="query"
              placeholder="Type a query"
              v-on:keyup.enter="getQuery"
              autofocus
              :loading="loading"
            ></v-text-field>
          </v-col>
        </v-row>

        <!-- configuration and clear/search -->
        <v-row justify="center">
          <!-- configuration panel -->
          <v-col cols="6" no-gutters>
            <v-expansion-panels v-model="configuration.open">
              <v-expansion-panel :disabled="loading">
                <v-expansion-panel-header v-slot="{ open }">
                  <v-row no-gutters>
                    <v-fade-transition leave-absolute>
                      <span v-if="open"
                        ><v-icon>mdi-tune</v-icon> Configuration</span
                      >
                      <v-row v-else no-gutters style="width: 100%" align="center">
                        <v-col
                          v-if="configuration.whole_words"
                          cols="4"
                          class="text--secondary"
                          >Match whole words</v-col
                        >
                        <v-col
                          v-else
                          cols="4"
                          class="text--secondary"
                          >Normal match</v-col
                        >
                        <v-col
                          cols="4"
                          class="text--secondary"
                          >≥ {{configuration.min_matches}} match<span v-if="configuration.min_matches!=1">es</span> per page</v-col
                        >
                        <v-col
                          v-if="configuration.software"
                          cols="4"
                          class="text--secondary"
                          >Use {{configuration.num_threads}} CPU thread<span v-if="configuration.num_threads!=1">s</span></v-col
                        >
                        <v-col
                          v-else
                          cols="4"
                          class="text--secondary"
                          >Use Alveo</v-col
                        >
                      </v-row>
                    </v-fade-transition>
                  </v-row>
                </v-expansion-panel-header>

                <!-- Configuration modifications -->
                <v-expansion-panel-content>
                  <v-row no-gutters align="center" justify="center">
                    <v-col offset="1" cols="5">
                      <v-switch
                        v-model="configuration.whole_words"
                        label="Whole words"
                        inset
                        color="primary"
                      ></v-switch>
                    </v-col>
                    <v-col align-self="center" cols="6">
                      <v-row
                        no-gutters
                        align="center"
                        justify="center"
                        class="text--secondary"
                      >
                        Minimum number of matches: {{configuration.min_matches}}
                      </v-row>
                      <v-row no-gutters
                        align="center"
                        justify="center"
                      >
                        <v-slider
                          min="1"
                          v-model="configuration.min_matches"
                          thumb-label
                        ></v-slider>
                      </v-row>
                    </v-col>
                    <v-col offset="1" cols="5">
                      <v-switch
                        v-model="configuration.software"
                        label="Run on CPU"
                        inset
                        color="primary"
                      ></v-switch>
                    </v-col>
                    <v-col align-self="center" cols="6">
                      <v-row
                        no-gutters
                        align="center"
                        justify="center"
                        class="text--secondary"
                      >
                        Number of CPU threads: {{configuration.num_threads}}
                      </v-row>
                      <v-row no-gutters
                        align="center"
                        justify="center"
                      >
                        <v-slider
                          min="1"
                          max="40"
                          :disabled="!configuration.software"
                          v-model="configuration.num_threads"
                          thumb-label
                        ></v-slider>
                      </v-row>
                    </v-col>
                  </v-row>
                </v-expansion-panel-content>
              </v-expansion-panel>
            </v-expansion-panels>
          </v-col>
          <v-col justify="end" cols="4" no-gutters>
            <div style="text-align: end; width: 100%">
              <v-btn
                color="blue-grey"
                @click="clear"
                text
                :disabled="query === undefined && response === undefined"
                ><v-icon>mdi-close</v-icon> clear</v-btn
              >
              <v-btn
                color="teal"
                @click="getQueryCPU"
                text
                :disabled="query === undefined || loading === true"
                ><v-icon>mdi-magnify</v-icon> CPU</v-btn
              >
              <v-btn
                color="light-blue"
                @click="getQueryAlveo"
                text
                :disabled="query === undefined || loading === true"
                ><v-icon>mdi-magnify</v-icon> Alveo</v-btn
              >
            </div>
          </v-col>
        </v-row>
        <v-row>
          <v-divider></v-divider>
        </v-row>
      </v-container>

      <!--<v-container v-if="!response && !loading">
        <v-row justify="center">
          <v-col cols="9">
            <p style="font-size: 1.2em; text-align: justify; text-align-last: center">
              Type a query above to search a Wikipedia database dump for a word or
              part of a word,<br/><span class="font-weight-bold">without an index</span>.
            </p>
            <p style="text-align: justify; text-align-last: center">
              The database dump was pre-downloaded and transformed into
              <span class="font-weight-bold">Apache Arrow</span> IPC format using
              <span class="font-weight-bold">Apache Spark</span>. To make things a bit
              more interesting, the article text is compressed with
              <span class="font-weight-bold">Google Snappy</span> - the default
              compression format of <span class="font-weight-bold">Apache Parquet</span>.
              The resulting dataset is about 22GB in size for the English Wikipedia
              without meta pages. The dataset is cached onto the local DDR banks of a
              <span class="font-weight-bold">Xilinx Alveo U200</span> FPGA accelerator
              card. The FPGA design consists of 45 RTL Snappy decompression engines
              and pattern matchers, fed with streaming Arrow data through a
              <span class="font-weight-bold">Fletcher</span> interface, and integrated
              with <span class="font-weight-bold">SDAccel</span>. For comparison, the
              algorithm can also be run on CPU, using up to forty Intel Xeon Silver
              4114 processor threads.
            </p>
          </v-col>
        </v-row>
      </v-container>-->

      <v-container v-if="!response && !loading">
        <v-row justify="center">
          <v-col cols="10" style="text-align: center">
            <p class="display-2 font-weight-light" style="margin-bottom: 25px; margin-top: 25px">
              Accelerate big data applications with ease
            </p>
            <p class="display-1 font-weight-light" style="margin-bottom: 40px; text-transform: uppercase">
              using Fletcher and Xilinx Alveo
            </p>
          </v-col>
        </v-row>
        <v-row justify="center" no-gutters>
          <v-col cols="10" no-gutters>
            <v-row justify="center" no-gutters>
              <v-spacer></v-spacer>
              <v-col align="center" justify="center" no-gutters>
                <img src="../assets/spark-logo.png" height="60px" cols="auto" />
              </v-col>
              <v-spacer></v-spacer>
              <v-col align="center" justify="center" no-gutters>
                <img src="../assets/arrow-logo.svg" height="55px" cols="auto" style="margin-top: 5px"/>
              </v-col>
              <v-spacer></v-spacer>
              <v-col align="center" justify="center" no-gutters>
                <!--<img src="../assets/fletcher-logo.png" height="60px" cols="auto" />-->
                <img src="../assets/fletcher-old-logo.png" height="60px" cols="auto" />
                <!--<img src="https://repository-images.githubusercontent.com/120948886/c0dcc400-80aa-11e9-8a51-c7ff5364fe0a" height="60px" cols="auto" />-->
              </v-col>
              <v-spacer></v-spacer>
              <v-col align="center" justify="center" no-gutters>
                <img src="../assets/xilinx-alveo-logo.png" height="55px" cols="auto" />
              </v-col>
              <v-spacer></v-spacer>
            </v-row>
          </v-col>
        </v-row>
        <v-row justify="center">
          <v-col cols="10" style="text-align: center">
            <p class="headline font-weight-light" style="margin-top: 25px; margin-bottom: 40px">
              Type a query to search through a Snappy-compressed Arrow table containing all of English Wikipedia in real-time!
            </p>
            <p style="margin-bottom: 8px">
              <v-icon color="light-blue darken-1">mdi-check</v-icon>
              Time to initial solution: two days — two weeks total to optimize
            </p>
            <p style="margin-bottom: 8px">
              <v-icon color="light-blue darken-1">mdi-check</v-icon>
              Seamless integration with big-data frameworks through Arrow and Fletcher
            </p>
            <p style="margin-bottom: 8px">
              <v-icon color="light-blue darken-1">mdi-check</v-icon>
              Open-source hardware Snappy decompression — easily saturating PCI Express 3.0 x16
            </p>
          </v-col>
        </v-row>
        <v-row justify="center">
          <img src="../assets/stack.svg" height="200px" cols="auto" style="margin-bottom: 50px"/>
        </v-row>
      </v-container>

      <v-container v-if="response || loading">
        <v-row justify="center" align="center" style="min-height: 175px">
          <v-col cols="4">
            <v-row align="center" no-gutters>
              <v-col cols=12 style="text-align: center">
                Execution time
              </v-col>
            </v-row>
            <v-row align="center" no-gutters style="padding-top: 10px">
              <v-col cols=3 no-gutters class="caption" style="text-align: right">
                ALVEO
              </v-col>
              <v-col cols=6 no-gutters style="padding-left: 10px; padding-right: 10px">
                <v-progress-linear
                  :value="hw_time / 200"
                  color="light-blue"
                  height="16px"
                  style="transition-duration: 0s"
                />
              </v-col>
              <v-col cols=3 no-gutters>
                <span v-if="hw_time !== undefined" class="font-weight-bold">{{hw_time}} ms</span>
                <span v-else class="text--secondary font-italic">Unknown</span>
              </v-col>
            </v-row>
            <v-row align="center" no-gutters style="padding-top: 10px">
              <v-col cols=3 no-gutters class="caption" style="text-align: right">
                CPU
              </v-col>
              <v-col cols=6 no-gutters style="padding-left: 10px; padding-right: 10px">
                <v-progress-linear
                  :value="sw_time / 200"
                  color="teal"
                  height="16px"
                  style="transition-duration: 0s"
                />
              </v-col>
              <v-col cols=3 no-gutters>
                <span v-if="sw_time !== undefined" class="font-weight-bold">{{sw_time}} ms</span>
                <span v-else class="text--secondary font-italic">Unknown</span>
              </v-col>
            </v-row>
            <v-row align="center" no-gutters style="padding-top: 10px">
              <v-col cols=12 style="text-align: center">
                <span v-if="!loading && sw_time !== undefined && hw_time !== undefined">
                  Done! Alveo speedup:
                  <span class="font-weight-bold">{{(sw_time / hw_time).toFixed(2)}}x</span>
                </span>
                <span v-else-if="loading && configuration.software">Running on CPU...</span>
                <span v-else-if="loading && !configuration.software">Running on Alveo...</span>
                <span v-else>Ready</span>
              </v-col>
            </v-row>
          </v-col>
          <v-col cols="5">
            <p style="font-size: 1.2em; text-align: justify; text-align-last: right" v-if="response">
              <span class="font-weight-bold">{{response.stats.num_word_matches}}</span>
              word<span v-if="response.stats.num_word_matches!=1">s</span>
              matched across
              <span class="font-weight-bold">{{response.stats.num_page_matches}}</span>
              page<span v-if="response.stats.num_page_matches!=1">s</span>,<br/>
              of which
              <span v-if="response.stats.num_result_records!=response.stats.num_page_matches">
                the first <span class="font-weight-bold">{{response.stats.num_result_records}}</span>
                page match<span v-if="response.stats.num_result_records!=1">es were</span>
                <span v-else>was</span>
              </span>
              <span v-else>
                all page matches were
              </span>
              recorded.
            </p>
            <p style="text-align: justify; text-align-last: right" v-if="response">
              The query took
              <span class="font-weight-bold">{{response.stats.time_taken_ms}} ms</span>
              <span v-if="response.query.mode == 0">on Alveo,</span>
              <span v-else>with {{response.query.mode}} thread<span v-if="response.query.mode != 1">s,</span></span>
              making the equivalent<br/>compressed article text bandwidth approximately
              <span class="font-weight-bold">{{response.stats.bandwidth}}</span>.
            </p>
          </v-col>
        </v-row>
        <v-row>
          <v-divider></v-divider>
        </v-row>
      </v-container>

      <v-container v-if="loading">
        <v-row justify="center" class="title">
          Loading...
        </v-row>
      </v-container>

      <v-container v-if="response">
        <v-row justify="center" class="title" v-if="response.top_result">
          Top results for "{{response.query.pattern}}"
        </v-row>
        <v-row justify="center" class="title" v-else>
          No results found for "{{response.query.pattern}}"
        </v-row>
        <v-row v-if="response.top_result" justify="center">
          <v-col cols="6">
            <v-card outlined>
              <v-img
                class="align-end"
                :src="'wiki_img?wiki=' + response.query.wiki + '&article=' + response.top_result[0]"
                height="400px"
                gradient="to bottom, rgba(0,0,0,.05), rgba(0,0,0,.3)"
              >
                <v-card-title class="headline white--text">
                  <a
                    :href="'https://' + response.query.wiki + '.wikipedia.org/wiki/' + response.top_result[0]"
                    target="_blank"
                    style="color: white"
                  >
                    {{response.top_result[0]}}
                  </a>
                </v-card-title>
              </v-img>
              <v-card-subtitle class="overline">TOP RESULT</v-card-subtitle>
              <v-card-actions>
                <!-- <v-btn text color="orange darken-4">{{ response.top_result[0] }}</v-btn> -->
                <v-spacer></v-spacer>
                <v-chip>{{ response.top_result[1] }}</v-chip>
              </v-card-actions>
            </v-card>
          </v-col>
        </v-row>
        <v-row justify="center">
          <v-col cols="9">
            <v-row v-if="response.top_result && response.top_ten_results" justify="center" dense>
              <v-col cols="4" v-for="(result, idx) in response.top_ten_results">
                <v-card outlined>
                  <v-img
                    class="align-end"
                    :src="'wiki_img?wiki=' + response.query.wiki + '&article=' + result[0]"
                    height="200px"
                    gradient="to bottom, rgba(0,0,0,.05), rgba(0,0,0,.3)"
                  >
                    <v-card-title class="headline white--text">
                      <a
                        :href="'https://' + response.query.wiki + '.wikipedia.org/wiki/' + result[0]"
                        target="_blank"
                        style="color: white"
                      >
                        {{result[0]}}
                      </a>
                    </v-card-title>
                  </v-img>
                  <v-card-subtitle class="overline">RESULT #{{idx + 2}}</v-card-subtitle>
                  <v-card-actions>
                    <!-- <v-btn text color="orange darken-4">{{ result[0] }}</v-btn> -->
                    <v-spacer></v-spacer>
                    <v-chip>{{ result[1] }}</v-chip>
                  </v-card-actions>
                </v-card>
              </v-col>
            </v-row>
          </v-col>
        </v-row>
        <v-row v-if="response.top_result && response.other_results">
          <v-divider></v-divider>
        </v-row>
        <v-row v-if="response.top_result && response.other_results && response.top_ten_results.length == 0" justify="center">
          <v-col cols="5">
            <p style="text-align: justify; text-align-last: center">
              Note: one or more kernels ran out of output buffer space, so not all
              page matches could be recorded to be sorted. Increase the minimum
              number of matches required per page to work around this!
            </p>
          </v-col>
        </v-row>
        <v-row v-if="response.top_result && response.other_results" justify="center">
          <v-col cols="4">
            <v-list disabled dense>
              <v-list-item v-for="(result, idx) in response.other_results">
                <v-list-item-content>
                  <v-list-item-title>
                    <span
                      v-if="response.top_ten_results.length != 0"
                      class="text--secondary"
                    >
                      #{{response.top_ten_results.length + idx + 2}}
                    </span>
                    <a :href="'https://' + response.query.wiki + '.wikipedia.org/wiki/' + result[0]" target="_blank">
                      {{result[0]}}
                    </a>
                  </v-list-item-title>
                </v-list-item-content>
                <v-list-item-avatar>
                  <v-chip>{{result[1]}}</v-chip>
                </v-list-item-avatar>
              </v-list-item>
            </v-list>
          </v-col>
        </v-row>

        <!-- <v-row>
          <v-expansion-panels v-if="result && result.results" accordion>
            <v-expansion-panel v-for="result in result.results">
              <v-expansion-panel-header>
                {{ result[0] }}
                <template v-slot:actions>
                  <v-chip color="primary">{{ result[1] }}</v-chip>
                </template>
              </v-expansion-panel-header>
              <v-expansion-panel-content> </v-expansion-panel-content>
            </v-expansion-panel>
          </v-expansion-panels>
        </v-row> -->
        <!--<v-row v-if="response && response.stats">
          <v-alert outlined color="primary" v-if="!loading && response.query">
            <p>{{ response }}</p>
          </v-alert>
        </v-row>-->
      </v-container>

      <div style="height: 90px"></div>
    </v-content>

    <v-footer class="grey lighten-3" style="position: fixed; left: 0px; right: 0px; bottom: 0px">
      <v-container>
        <v-row align="end" justify="center" no-gutters>
          <v-spacer></v-spacer>
          <v-col self-align="center" align="start" cols="4">
            <div v-if="server_status">
              <v-row align="center" no-gutters>
                <v-col cols=3 no-gutters class="text--secondary overline" style="text-align: right">
                  Server status
                </v-col>
                <v-col cols=9 no-gutters class="caption" style="padding-left: 10px">
                  {{server_status.status}}
                </v-col>
              </v-row>
              <v-row align="center" no-gutters>
                <v-col cols=3 no-gutters class="text--secondary overline" style="text-align: right">
                  Alveo total
                </v-col>
                <v-col cols=6 no-gutters style="padding-left: 10px; padding-right: 10px">
                  <v-progress-linear
                    :value="server_status.power_in * 1.5"
                    color="light-blue"
                    height="7px"
                    style="transition-duration: 0.5s"
                  />
                </v-col>
                <v-col cols=3 no-gutters class="caption" style="text-align: left">
                  {{(server_status.power_in).toFixed(1)}} W
                </v-col>
              </v-row>
              <v-row align="center" no-gutters>
                <v-col cols=3 no-gutters class="text--secondary overline" style="text-align: right">
                  Alveo VCCint
                </v-col>
                <v-col cols=6 no-gutters style="padding-left: 10px; padding-right: 10px">
                  <v-progress-linear
                    :value="server_status.power_vccint * 1.5"
                    color="light-blue"
                    height="7px"
                    style="transition-duration: 0.5s"
                  />
                </v-col>
                <v-col cols=3 no-gutters class="caption" style="text-align: left">
                  {{(server_status.power_vccint).toFixed(1)}} W
                </v-col>
              </v-row>
            </div>
          </v-col>
          <v-spacer></v-spacer>
          <v-col align="center" justify="center">
            <img src="../assets/xilinx-logo.svg" height="40px" cols="auto" style="margin-bottom: 4px" />
          </v-col>
          <v-spacer></v-spacer>
          <v-col align="center" justify="center">
            <img src="../assets/fitoptivis-logo.png" height="50px" cols="auto" />
          </v-col>
          <v-spacer></v-spacer>
          <v-col align="center" justify="center">
            <img src="../assets/tudelft-logo.svg" height="50px" cols="auto" style="margin-bottom: 10px" />
          </v-col>
          <v-spacer></v-spacer>
          <v-col align="center" justify="center">
            <!--<img src="../assets/fletcher-logo.png" height="50px" cols="auto" />-->
            <img src="../assets/fletcher-old-logo.png" height="50px" cols="auto" />
            <!--<img src="https://repository-images.githubusercontent.com/120948886/c0dcc400-80aa-11e9-8a51-c7ff5364fe0a" height="50px" cols="auto" />-->
          </v-col>
          <v-spacer></v-spacer>
          <!-- not sure about the license for this one since we're not in any way affiliated
          <v-col align="center" justify="center" cols="2">
            <img src="../assets/wikipedia-logo.svg" height="50px" />
          </v-col>-->
        </v-row>
      </v-container>
    </v-footer>
  </v-app>
</template>

<script>
import Vue from "vue";

export default Vue.extend({
  data() {
    return {
      configuration: {
        open: false,
        whole_words: false,
        min_matches: 1,
        software: false,
        num_threads: 40
      },
      query: undefined,
      response: undefined,
      loading: false,
      timer: undefined,
      sw_time: undefined,
      hw_time: undefined,
      timer_start: 0.0,
      server_status: undefined
    };
  },
  mounted: function() {
    this.update_status();
  },
  methods: {
    clear: function() {
      this.query = undefined;
      this.loading = false;
      this.response = undefined;
      clearInterval(this.timer);
      this.sw_time = undefined;
      this.hw_time = undefined;
      this.$refs.query.focus();
    },
    getQueryAlveo: function() {
      this.configuration.software = false;
      this.getQuery();
    },
    getQueryCPU: function() {
      this.configuration.software = true;
      this.getQuery();
    },
    getQuery: function() {
      if (this.loading) {
        return;
      }
      if (!this.query || this.query === "") {
        return;
      }
      var mode = this.configuration.software ? this.configuration.num_threads : 0;
      this.loading = true;
      this.response = undefined;
      this.configuration.open = false;
      if (this.configuration.software) {
        this.sw_time = 0;
      } else {
        this.hw_time = 0;
      }
      this.timer_start = performance.now();
      this.timer = setInterval(() => {
        var time = Math.round(performance.now() - this.timer_start - Math.random() * 20 - 100)
        if (time < 0) {
          time = 0;
        }
        if (this.configuration.software) {
          if (time < this.sw_time) {
            this.sw_time += 1;
          } else {
            this.sw_time = time;
          }
        } else {
          if (time < this.hw_time) {
            this.hw_time += 1;
          } else {
            this.hw_time = time;
          }
        }
      }, 50)
      fetch(
        `query?pattern=${this.query}&whole_words=${this.configuration.whole_words}&min_matches=${this.configuration.min_matches}&mode=${mode}`
      ).then(res => res.json()).then(res => {
        if (this.loading) {
          clearInterval(this.timer);
          if (this.configuration.software) {
            this.sw_time = res.stats.time_taken_ms;
          } else {
            this.hw_time = res.stats.time_taken_ms;
          }
          this.loading = false;
          this.response = res;
//           if (!this.configuration.software) {
//             this.configuration.software = true;
//             this.getQuery();
//           } else {
//             this.configuration.software = false;
//           }
        }
      })
    },
    update_status: function() {
      fetch('status').then(res => res.json()).then(res => {
        this.server_status = res;
        setTimeout(this.update_status, 300);
      })
    }
  }
});
</script>

<style>
.v-input input {
  max-height: 900em;
}
.v-expansion-panel::before {
  box-shadow: none;
}
</style>
